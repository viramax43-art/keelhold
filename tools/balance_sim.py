#!/usr/bin/env python3
"""
Balance simulator for Bridge Defense (ported idea from slime-factory-tycoon).

Parses the game's Luau configs directly (single source of truth) and simulates
a player grinding waves to answer:

 * When does the FIRST prestige happen? (target: 12-30 min — hook before churn)
 * Which wave does the player reach in a session?
 * Are there progression stalls? (long wall = churn point)
 * How much does income grow per prestige?

Usage:
    python tools/balance_sim.py
    python tools/balance_sim.py --hours 3 --check
    python tools/balance_sim.py --json

Zero dependencies. Configs parsed from:
    src/Shared/Config/GameConfig.lua
    src/Shared/Config/UpgradesConfig.lua
    src/Shared/Config/WeaponsConfig.lua
    src/Shared/Config/EnemiesConfig.lua
    src/Shared/Util/WaveScaling.lua
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Health targets (Slime Factory uses: zone2 < 5min, first rebirth 8-30 min,
# stall < 45 min). Adapted to a wave-defense game session (~30-60 min).
TARGETS = {
    "first_prestige_min_min": 10.0,   # too early = prestige feels free
    "first_prestige_min_max": 35.0,   # too late = players quit before seeing it
    "max_stall_minutes": 8.0,         # no new purchase for this long = boring
    "wave_at_60min_min": 12,          # should get meaningfully far in an hour
}


def _num(raw: str) -> float:
    raw = raw.strip()
    raw = raw.replace("_", "")
    return float(raw)


# ------------------------------------------------------------------ parsing

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def parse_game_config() -> dict:
    t = read("src/Shared/Config/GameConfig.lua")
    def num(key, default):
        m = re.search(rf"{key}\s*=\s*([\d.]+)", t)
        return _num(m.group(1)) if m else default
    return {
        "checkpoint_interval": int(num("CheckpointInterval", 5)),
        "enemies_base": num("EnemiesPerWaveBase", 12),
        "enemies_growth": num("EnemiesPerWaveGrowth", 2),
        "enemies_cap": num("MaxEnemiesPerWave", 100),
        "wave_gold_bonus": num("GoldBonus", 35),
        "wave_xp_bonus": num("XPBonus", 15),
        "wave_bonus_per_wave": num("BonusPerWave", 4),
        "checkpoint_mult": num("CheckpointMult", 3),
        "defense_bots": int(num("DefenseBotCount", 4)),
    }


def _f(block: str, key: str, default: float | None = None) -> float | None:
    m = re.search(rf"{key}\s*=\s*([-\d.eE]+)", block)
    return _num(m.group(1)) if m else default


def parse_upgrades() -> dict:
    t = read("src/Shared/Config/UpgradesConfig.lua")
    stats = {}
    for m in re.finditer(r"(\w+)\s*=\s*\{(.*?)\},", t, re.S):
        key, blk = m.group(1), m.group(2)
        if key not in ("HP", "Accuracy", "ReloadSpeed"):
            continue
        if _f(blk, "BaseValue") is None or _f(blk, "XPCostBase") is None:
            continue
        stats[key] = {
            "base": _f(blk, "BaseValue"),
            "per_level": _f(blk, "PerLevel"),
            "xp_cost_base": _f(blk, "XPCostBase"),
            "xp_cost_growth": _f(blk, "XPCostGrowth"),
        }
    pm = re.search(r"Prestige\s*=\s*\{(.*?)\n\s*\}", t, re.S)
    prestige = {"threshold": 30, "threshold_growth": 15, "stat_bonus": 0.02, "income_bonus": 0.05}
    if pm:
        blk = pm.group(1)
        for key, attr in (
            ("Threshold", "threshold"),
            ("ThresholdGrowth", "threshold_growth"),
            ("StatBonusPerPoint", "stat_bonus"),
            ("IncomeBonusPerPoint", "income_bonus"),
        ):
            mm = re.search(rf"{key}\s*=\s*([\d.]+)", blk)
            if mm:
                prestige[attr] = _num(mm.group(1))
    return {"stats": stats, "prestige": prestige}


def parse_weapons() -> dict:
    t = read("src/Shared/Config/WeaponsConfig.lua")
    weapons = {}
    # each weapon block:  Wtype = { [1] = {...}, ... [5] = {...} },
    for m in re.finditer(r"(\w+)\s*=\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\},", t):
        wtype, body = m.group(1), m.group(2)
        tiers = {}
        for tm in re.finditer(r"\[(\d+)\]\s*=\s*\{([^{}]*)\}", body):
            blk = tm.group(2)
            if _f(blk, "Damage") is None:
                continue
            tiers[int(tm.group(1))] = {
                "cost": _f(blk, "GoldCost", 0),
                "damage": _f(blk, "Damage"),
                "fire_rate": _f(blk, "FireRate", 0.5),
            }
        if len(tiers) >= 2:
            weapons[wtype] = tiers
    # elite tiers are generated at runtime — replicate the generator
    for wtype, tiers in list(weapons.items()):
        if 5 not in tiers:
            continue
        for tier in range(6, 11):
            prev = tiers[tier - 1]
            tiers[tier] = {
                "cost": math.floor(prev["cost"] * 2.6 / 100) * 100,
                "damage": math.floor(prev["damage"] * 1.22),
                "fire_rate": max(0.03, prev["fire_rate"] * 0.97),
                "prestige_req": tier - 5,
            }
    return weapons


def parse_enemies() -> dict:
    t = read("src/Shared/Config/EnemiesConfig.lua")
    def num(key, default, block=None):
        src = block or t
        m = re.search(rf"{key}\s*=\s*([-\d.]+)", src)
        return _num(m.group(1)) if m else default
    base_block = re.search(r"BaseStats\s*=\s*\{(.*?)\},", t, re.S)
    scale_block = re.search(r"PerWaveScaling\s*=\s*\{(.*?)\},", t, re.S)
    era_block = re.search(r"EndlessEra\s*=\s*\{(.*?)\},", t, re.S)
    rewards_block = re.search(r"Rewards\s*=\s*\{(.*?)\},", t, re.S)
    bb = base_block.group(1) if base_block else ""
    sb = scale_block.group(1) if scale_block else ""
    eb = era_block.group(1) if era_block else ""
    rb = rewards_block.group(1) if rewards_block else ""
    return {
        "hp": num("HP", 60, bb),
        "damage": num("Damage", 8, bb),
        "hp_scale": num("HP", 0.12, sb),
        "armor_scale": num("Armor", 0.6, sb),
        "era_start": int(num("StartWave", 20, eb)),
        "era_hp_growth": num("HPGrowth", 1.07, eb),
        "kill_gold": num("Gold", 12, rb),
        "kill_xp": num("XP", 8, rb),
        "wave_growth": num("WaveGrowth", 0.08, rb),
        "max_wave_mult": num("MaxWaveMult", 6, rb),
    }


# ------------------------------------------------------------------ simulation

@dataclass
class Player:
    gold: float = 100.0  # starting gold from ProfileTemplate
    xp: float = 0.0
    total_xp: float = 0.0
    prestige: int = 0
    upgrades: dict = field(default_factory=lambda: {"HP": 0, "Accuracy": 0, "ReloadSpeed": 0})
    weapons: dict = field(default_factory=dict)  # wtype -> tier owned
    weapon_type: str = "Pistol"

    def owned_tier(self, wtype):
        return self.weapons.get(wtype, 1 if wtype == "Pistol" else 0)


def stat_value(cfg_stat, level, prestige, prestige_cfg):
    base = cfg_stat["base"] + cfg_stat["per_level"] * level
    return base * (1 + prestige * prestige_cfg["stat_bonus"])


def simulate(cfg, ups, weapons, en, hours: float, verbose: bool) -> dict:
    p = Player()
    prestige_cfg = ups["prestige"]
    wave = 1
    t = 0.0  # seconds
    end_t = hours * 3600
    events = []
    last_progress_t = 0.0
    max_stall = 0.0
    first_prestige_min = None

    def income_wave_mult(w):
        return min(1 + en["wave_growth"] * (w - 1), en["max_wave_mult"])

    def prestige_income_mult():
        return 1 + p.prestige * prestige_cfg["income_bonus"]

    def player_dps():
        tiers = weapons[p.weapon_type]
        tier = min(p.owned_tier(p.weapon_type), max(tiers))
        w = tiers[tier]
        reload_mult = stat_value(ups["stats"]["ReloadSpeed"], p.upgrades["ReloadSpeed"], p.prestige, prestige_cfg)
        accuracy = stat_value(ups["stats"]["Accuracy"], p.upgrades["Accuracy"], p.prestige, prestige_cfg)
        return (w["damage"] / w["fire_rate"]) * reload_mult * accuracy

    def bot_dps():
        # 4 bots with starter pistols inheriting host upgrades
        w = weapons["Pistol"][1]
        reload_mult = stat_value(ups["stats"]["ReloadSpeed"], p.upgrades["ReloadSpeed"], p.prestige, prestige_cfg)
        return cfg["defense_bots"] * (w["damage"] / w["fire_rate"]) * reload_mult * 0.8

    def enemy_hp(w):
        mult = 1 + en["hp_scale"] * (w - 1)
        if w > en["era_start"]:
            mult *= en["era_hp_growth"] ** (w - en["era_start"])
        return en["hp"] * mult

    def wave_enemy_count(w):
        return min(cfg["enemies_base"] + cfg["enemies_growth"] * (w - 1), cfg["enemies_cap"])

    while t < end_t:
        n = wave_enemy_count(wave)
        total_hp = enemy_hp(wave) * n
        dps = player_dps() + bot_dps()
        wave_time = total_hp / max(dps, 0.01) + 8.0  # +8s inter-wave delay
        t += wave_time

        wm = income_wave_mult(wave)
        gold_gain = (en["kill_gold"] * n * wm
                     + (cfg["wave_gold_bonus"] + cfg["wave_bonus_per_wave"] * wave)
                       * (cfg["checkpoint_mult"] if wave % cfg["checkpoint_interval"] == 0 else 1))
        xp_gain = (en["kill_xp"] * n * wm
                   + (cfg["wave_xp_bonus"] + cfg["wave_bonus_per_wave"] * wave)
                     * (cfg["checkpoint_mult"] if wave % cfg["checkpoint_interval"] == 0 else 1))
        p.gold += gold_gain * prestige_income_mult()
        p.xp += xp_gain * prestige_income_mult()
        p.total_xp += xp_gain * prestige_income_mult()

        # --- spending AI: greedy best-value, weapons first if big DPS gain
        bought = True
        while bought:
            bought = False
            # 1) weapon upgrades (next tier of current weapon; swap if better dps/gold)
            cur_tier = p.owned_tier(p.weapon_type)
            candidates = []
            for wtype, tiers in weapons.items():
                owned = p.owned_tier(wtype)
                nxt = owned + 1 if owned > 0 else 1
                if nxt not in tiers:
                    continue
                wt = tiers[nxt]
                if wt.get("prestige_req", 0) > p.prestige:
                    continue
                if wt["cost"] > p.gold:
                    continue
                # dps after purchase
                reload_mult = stat_value(ups["stats"]["ReloadSpeed"], p.upgrades["ReloadSpeed"], p.prestige, prestige_cfg)
                new_dps = (wt["damage"] / wt["fire_rate"]) * reload_mult
                gain = new_dps - player_dps()
                if gain > 0:
                    candidates.append((gain / wt["cost"], wtype, nxt, wt))
            # 2) xp stat upgrades (best value: dps-ish gain per xp)
            stat_candidates = []
            for key, cfg_stat in ups["stats"].items():
                lvl = p.upgrades[key]
                cost = math.floor(cfg_stat["xp_cost_base"] * (cfg_stat["xp_cost_growth"] ** lvl))
                if cost > p.xp:
                    continue
                # approximate value
                if key == "ReloadSpeed":
                    gain = player_dps() * (cfg_stat["per_level"] / max(cfg_stat["base"] + cfg_stat["per_level"] * lvl, 0.01))
                elif key == "Accuracy":
                    gain = player_dps() * 0.3 * (cfg_stat["per_level"] / max(cfg_stat["base"] + cfg_stat["per_level"] * lvl, 0.01))
                else:
                    gain = 0  # HP doesn't speed up clears
                stat_candidates.append((gain / max(cost, 1), key, cost))
            stat_candidates.sort(reverse=True)
            candidates.sort(reverse=True)

            # prefer weapon if its dps/gold is comparable; else cheapest stat upgrade
            did = False
            if stat_candidates and stat_candidates[0][0] > 0:
                _, key, cost = stat_candidates[0]
                p.xp -= cost
                p.upgrades[key] += 1
                did = True
                bought = True
            if candidates and (not did or candidates[0][0] > 2 * (stat_candidates[0][0] if stat_candidates else 0)):
                _, wtype, nxt, wt = candidates[0]
                p.gold -= wt["cost"]
                p.weapons[wtype] = nxt
                if p.owned_tier(wtype) > p.owned_tier(p.weapon_type) or wtype == p.weapon_type:
                    # switch to best owned weapon by dps
                    best_w, best_d = p.weapon_type, 0
                    for w2, tiers2 in weapons.items():
                        o = p.owned_tier(w2)
                        if o > 0:
                            d = tiers2[min(o, max(tiers2))]["damage"] / tiers2[min(o, max(tiers2))]["fire_rate"]
                            if d > best_d:
                                best_d, best_w = d, w2
                    p.weapon_type = best_w
                bought = True
            if bought:
                last_progress_t = t

        # --- prestige
        total_levels = sum(p.upgrades.values())
        threshold = prestige_cfg["threshold"] + prestige_cfg["threshold_growth"] * p.prestige
        if total_levels >= threshold:
            p.prestige += 1
            p.upgrades = {"HP": 0, "Accuracy": 0, "ReloadSpeed": 0}
            if first_prestige_min is None:
                first_prestige_min = t / 60
            if p.prestige <= 5:
                events.append({"t_min": round(t / 60, 2), "event": f"Prestige #{p.prestige}"})
            last_progress_t = t

        if wave % 10 == 0:
            events.append({"t_min": round(t / 60, 2), "event": f"Wave {wave} cleared (dps={player_dps():.0f}, gold={p.gold:.0f})"})

        stall = (t - last_progress_t) / 60
        max_stall = max(max_stall, stall)

        # wipe check: if wave takes absurdly long, player is stuck
        if wave_time > 300:
            events.append({"t_min": round(t / 60, 2), "event": f"STUCK at wave {wave} (clear takes {wave_time/60:.1f} min)"})
            break
        wave += 1

    return {
        "hours": hours,
        "waves_cleared": wave - 1,
        "prestiges": p.prestige,
        "first_prestige_min": round(first_prestige_min, 2) if first_prestige_min else None,
        "final_dps": round(player_dps() + bot_dps(), 1),
        "gold": round(p.gold, 0),
        "max_stall_min": round(max_stall, 2),
        "weapon": f"{p.weapon_type} T{p.owned_tier(p.weapon_type)}",
        "events": events[:40],
    }


def check_health(res: dict) -> list[str]:
    problems = []
    fp = res["first_prestige_min"]
    if fp is None:
        problems.append("Player never prestiged — the core retention loop is unreachable.")
    else:
        if fp < TARGETS["first_prestige_min_min"]:
            problems.append(f"First prestige at {fp:.1f} min (target > {TARGETS['first_prestige_min_min']}). Too cheap; prestige feels meaningless.")
        if fp > TARGETS["first_prestige_min_max"]:
            problems.append(f"First prestige at {fp:.1f} min (target < {TARGETS['first_prestige_min_max']}). Most players quit before seeing it.")
    if res["max_stall_min"] > TARGETS["max_stall_minutes"]:
        problems.append(f"Longest stall {res['max_stall_min']:.1f} min without progress (target < {TARGETS['max_stall_minutes']}).")
    if res["waves_cleared"] < TARGETS["wave_at_60min_min"] and res["hours"] >= 1:
        problems.append(f"Only {res['waves_cleared']} waves in {res['hours']}h (target >= {TARGETS['wave_at_60min_min']} in 1h).")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description="Simulate Bridge Defense progression.")
    ap.add_argument("--hours", type=float, default=2.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    cfg = parse_game_config()
    ups = parse_upgrades()
    weapons = parse_weapons()
    en = parse_enemies()
    if not ups["stats"] or not weapons:
        print("error: failed to parse configs", file=sys.stderr)
        return 2

    res = simulate(cfg, ups, weapons, en, args.hours, args.verbose)

    if args.json:
        print(json.dumps(res, indent=2))
    else:
        print("=" * 62)
        print(f" BALANCE SIM -- Bridge Defense, {args.hours}h session")
        print("=" * 62)
        print(f" waves cleared    : {res['waves_cleared']}")
        print(f" prestiges        : {res['prestiges']}")
        print(f" first prestige   : {res['first_prestige_min']} min")
        print(f" final weapon     : {res['weapon']}")
        print(f" final dps        : {res['final_dps']}")
        print(f" longest stall    : {res['max_stall_min']} min")
        print("\n timeline:")
        for e in res["events"]:
            print(f" {e['t_min']:>9.2f} min  {e['event']}")
        problems = check_health(res)
        if problems:
            print("\n BALANCE WARNINGS:")
            for pr in problems:
                print(f"  ! {pr}")
            if args.check:
                return 1
        else:
            print("\n balance within target ranges.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
