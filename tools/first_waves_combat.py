#!/usr/bin/env python3
"""
First-waves combat validator for Bridge Defense (waves 1-5).

Answers one question: "are waves 1-5 tense but fair, and do bots outshoot
enemies at the same distance?"

Checks:
 * Pistol T1 (18 dmg) vs wave-1 enemy HP (108) -> ~6 hits to kill
 * Bots hit noticeably more often than enemies (profile 1.0 vs 0.8)
 * Distance matters: at max range almost everything misses, up close it hurts
 * Force-hit debug flags are OFF (they made every clear-LOS shot hit)
 * A wave is lost only when ALL bots are downed at the same time
 * Waves 1-5 are winnable but the squad takes real damage

The Luau curve (src/Shared/Util/AccuracyHelper.lua) is re-implemented 1:1 from
GameConfig.Battle.HitChance, so any config change shows up here immediately.
Enemy side mirrors EnemyService.SpawnWave: own weapons (EnemiesConfig.EnemyWeapons),
wave scaling via WaveScaling.EnemyStats, max 4 simultaneous melee attackers.

Usage:
    python tools/first_waves_combat.py
    python tools/first_waves_combat.py --check
    python tools/first_waves_combat.py --json
    python tools/first_waves_combat.py --log logs/game.log     # real telemetry
    python tools/first_waves_combat.py --trials 500 --seed 7
    python tools/first_waves_combat.py --lint                  # Luau syntax check via lune
    python tools/first_waves_combat.py --weapon-tier 2 --bot-hp 175   # upgraded squad

Zero dependencies (Lune is optional and only used by --lint). Sources:
    src/Shared/Config/GameConfig.lua, EnemiesConfig.lua, WeaponsConfig.lua,
    UpgradesConfig.lua, src/Shared/Util/WaveScaling.lua
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---- Simulation assumptions (bridge map + services behaviour) --------------
SPAWN_DISTANCE = 200.0      # enemy distance from the defense line at spawn
BOT_STANDOFF = 0.0          # bots stand on the defense line
ATTACK_STANDOFF = 4.5       # EnemiesConfig.AttackSpacing: melee attacker spot
MELEE_GATE = 18.0           # EnemiesConfig.MeleeRange: when slots get claimed
MELEE_SEARCH_BONUS = 8.0    # EnemyService line 545: melee search radius = arrive + 8
BOT_SPREAD = 8.0            # lateral gap between squad members on the defense line

# A player clears waves 1-4 (~22 kills + wave bonus, EnemiesConfig.Rewards 8 XP/kill)
# with roughly 200 XP, which buys ~5 HP levels (100 -> 175 HP) and ~4 Accuracy levels.
PROGRESSION_HP_LEVELS = 5
PROGRESSION_ACCURACY_LEVELS = 4
SIM_DT = 0.05               # == RunService.Heartbeat clamp in EnemyService
SIM_TIMEOUT = 120.0         # a wave that takes longer counts as a stall

# Hit-chance defaults, mirroring AccuracyHelper.DEFAULTS
HIT_DEFAULTS = {
    "Enabled": True,
    "BotProfileMult": 1.0,
    "EnemyProfileMult": 0.8,
    "NearFalloffStart": 0.15,
    "FalloffPower": 1.35,
    "MaxDistancePenalty": 0.55,
    "SpreadBase": 0.55,
    "SpreadWeight": 0.85,
    "MovingShooterPenalty": 0.10,
    "MovingTargetPenalty": 0.07,
    "MinChance": 0.05,
    "MaxChance": 0.92,
}


# --------------------------------------------------------------- parsing ----

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def _num(raw: str) -> float:
    return float(raw.strip().replace("_", ""))


def table_body(src: str, name: str) -> str:
    """Body of `name = { ... }` (brace-balanced, nesting safe)."""
    m = re.search(rf"\b{name}\s*=\s*\{{", src)
    if not m:
        return ""
    start = m.end() - 1
    depth = 0
    for i in range(start, len(src)):
        ch = src[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
    return ""


def fnum(block: str, key: str, default=None):
    if not block:
        return default
    m = re.search(rf"\b{key}\s*=\s*([-\d.eE]+)", block)
    return _num(m.group(1)) if m else default


def fbool(block: str, key: str, default: bool) -> bool:
    if not block:
        return default
    m = re.search(rf"\b{key}\s*=\s*(true|false)", block)
    return (m.group(1) == "true") if m else default


def _rows(block: str, keys) -> dict:
    """`Key = { a = 1, b = 2 }` rows -> {Key: {a: 1.0, b: 2.0}}."""
    out = {}
    for key in keys:
        body = table_body(block, key)
        if not body:
            continue
        row = {}
        for k, v in re.findall(r"(\w+)\s*=\s*([-\d.]+)", body):
            row[k] = _num(v)
        if row:
            out[key] = row
    return out


def parse_all() -> dict:
    game = read("src/Shared/Config/GameConfig.lua")
    enemies = read("src/Shared/Config/EnemiesConfig.lua")
    weapons = read("src/Shared/Config/WeaponsConfig.lua")
    upgrades = read("src/Shared/Config/UpgradesConfig.lua")

    battle = table_body(game, "Battle")
    waves = table_body(game, "Waves")
    hit_raw = table_body(battle, "HitChance")
    downed = table_body(battle, "Downed")
    hit = dict(HIT_DEFAULTS)
    for key in HIT_DEFAULTS:
        if key == "Enabled":
            hit[key] = fbool(hit_raw, key, HIT_DEFAULTS[key])
        else:
            hit[key] = fnum(hit_raw, key, HIT_DEFAULTS[key])

    override = {}
    for idx, value in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", table_body(waves, "EnemiesPerWaveOverride")):
        override[int(idx)] = int(value)

    base_stats = table_body(enemies, "BaseStats")
    scale = table_body(enemies, "PerWaveScaling")
    era = table_body(enemies, "EndlessEra")
    weapon_rotation = re.findall(r'"(\w+)"', table_body(enemies, "WeaponRotation"))

    upg_stats = table_body(upgrades, "Stats")
    upg = {}
    per_level = {}
    for name in ("HP", "Accuracy", "ReloadSpeed", "CritChance", "CritDamage", "BotDamage"):
        body = table_body(upg_stats, name)
        upg[name] = fnum(body, "BaseValue", None)
        per_level[name] = fnum(body, "PerLevel", 0.0)

    weapons_body = table_body(weapons, "Weapons")
    pistol = {}
    for tier, body in re.findall(r"\[(\d+)\]\s*=\s*\{([^{}]*)\}", table_body(weapons_body, "Pistol")):
        pistol[int(tier)] = {
            "damage": fnum(body, "Damage", 0.0),
            "fire_rate": fnum(body, "FireRate", 0.5),
            "range": fnum(body, "Range", 80.0),
            "accuracy": fnum(body, "Accuracy", 0.85),
            "spread": fnum(body, "Spread", 0.2),
        }

    max_enemies = int(fnum(waves, "MaxEnemiesPerWave", 100))
    count_by_wave = {w: int(min(max_enemies, override[w])) for w in override}

    return {
        "hit": hit,
        "upgrades": {"base": upg, "per_level": per_level},
        "force_hits": {
            "bot": fbool(battle, "ForceBotHitsForTest", False),
            "enemy": fbool(battle, "ForceEnemyHitsForTest", False),
        },
        "debug_combat": fbool(battle, "DebugCombatDamage", False),
        "engage": {
            "defense": fnum(battle, "DefenseEngageRange", 240.0),
            "player": fnum(battle, "PlayerEngageRange", 240.0),
        },
        "downed": {
            "enabled": fbool(downed, "Enabled", True),
            "revive_delay": fnum(downed, "ReviveDelaySec", 12.0),
            "revive_hp_percent": fnum(downed, "ReviveHPPercent", 0.35),
            "revive_on_wave_start": fbool(downed, "ReviveOnWaveStart", True),
        },
        "waves": {
            "base": fnum(waves, "EnemiesPerWaveBase", 12.0),
            "growth": fnum(waves, "EnemiesPerWaveGrowth", 2.0),
            "cap": max_enemies,
            "override": override,
            "count_by_wave": count_by_wave,
            "inter_wave_delay": fnum(waves, "InterWaveDelay", 6.0),
            "spawn_interval": fnum(battle, "EnemySpawnInterval", 0.5),
            "group_size": max(1, int(fnum(battle, "EnemyGroupSize", 3))),
            "group_gap": fnum(battle, "EnemyGroupGap", 1.2),
        },
        "bots": {
            "count": max(1, int(fnum(game, "DefenseBotCount", 4))),
            "hp": upg["HP"] if upg["HP"] is not None else 100.0,
            "upgrade_accuracy": upg["Accuracy"] if upg["Accuracy"] is not None else 0.75,
            "reload_mult": upg["ReloadSpeed"] if upg["ReloadSpeed"] is not None else 1.0,
            "crit_chance": upg["CritChance"] if upg["CritChance"] is not None else 0.0,
            "crit_damage": upg["CritDamage"] if upg["CritDamage"] is not None else 1.5,
            "bot_damage_mult": upg["BotDamage"] if upg["BotDamage"] is not None else 1.0,
            "weapon_type": "Pistol",
            "weapon_tier": 1,
            "accuracy_override": None,
            "hp_override": None,
        },
        "pistol_tiers": pistol,
        "enemies": {
            "hp": fnum(base_stats, "HP", 108.0),
            "damage": fnum(base_stats, "Damage", 13.0),
            "fire_rate": fnum(base_stats, "FireRate", 0.7),
            "accuracy": fnum(base_stats, "Accuracy", 0.55),
            "walk_speed": fnum(base_stats, "WalkSpeed", 12.0),
            "armor": fnum(base_stats, "Armor", 0.0),
            "hp_scale": fnum(scale, "HP", 0.12),
            "damage_scale": fnum(scale, "Damage", 0.035),
            "fire_scale": fnum(scale, "FireRate", -0.008),
            "accuracy_scale": fnum(scale, "Accuracy", 0.006),
            "armor_scale": fnum(scale, "Armor", 0.6),
            "speed_scale": fnum(scale, "WalkSpeed", 0.002),
            "era_start": int(fnum(era, "StartWave", 20)),
            "era_hp_growth": fnum(era, "HPGrowth", 1.04),
            "era_damage_growth": fnum(era, "DamageGrowth", 1.03),
            "min_fire_rate": fnum(enemies, "MinFireRate", 0.15),
            "weapons": _rows(table_body(enemies, "EnemyWeapons"), weapon_rotation),
            "types": _rows(table_body(enemies, "EnemyTypes"), weapon_rotation),
            "weapon_rotation": weapon_rotation,
            "range_growth_per_wave": fnum(enemies, "RangeGrowthPerWave", 0.0),
            "range_growth_cap": fnum(enemies, "RangeGrowthCap", 1.0),
            "attack_range": fnum(enemies, "AttackRange", 160.0),
            "melee_range": fnum(enemies, "MeleeRange", MELEE_GATE),
            "melee_damage_mult": fnum(enemies, "MeleeDamageMult", 1.1),
            "melee_fire_rate": fnum(enemies, "MeleeFireRate", 0.9),
            "lane_count": max(1, int(fnum(enemies, "LaneCount", 6))),
            "max_attackers": max(1, int(fnum(enemies, "MaxAttackers", 4))),
            "slots_per_lane": max(1, int(fnum(enemies, "AttackSlotsPerLane", 1))),
            "attack_spacing": fnum(enemies, "AttackSpacing", ATTACK_STANDOFF),
            "attack_arrive": fnum(enemies, "AttackArriveDistance", 1.5),
            "queue_spacing": fnum(enemies, "QueueSpacing", 5.5),
        },
    }


# ------------------------------------------------------------ combat math ---

def profile_mult(c: dict, side: str) -> float:
    """AccuracyHelper.GetProfileMult(side)."""
    hit = c["hit"]
    if side == "bot":
        return max(0.1, hit["BotProfileMult"])
    if side == "enemy":
        return max(0.1, hit["EnemyProfileMult"])
    return 1.0


def base_accuracy(weapon_acc: float, upgrade_acc: float) -> float:
    """AccuracyHelper.ComputeBaseAccuracy."""
    return min(max(weapon_acc * 0.55 + upgrade_acc * 0.45, 0.35), 0.95)


def distance_penalty(c: dict, distance: float, max_range: float, spread: float) -> float:
    """AccuracyHelper.DistancePenalty."""
    hit = c["hit"]
    rng = max(1.0, max_range)
    start = min(max(hit["NearFalloffStart"], 0.0), 0.9)
    t = (max(0.0, distance) / rng - start) / max(0.05, 1.0 - start)
    t = min(max(t, 0.0), 1.0)
    spread_mult = hit["SpreadBase"] + min(max(spread, 0.0), 1.0) * hit["SpreadWeight"]
    power = max(0.25, hit["FalloffPower"])
    return max(0.0, hit["MaxDistancePenalty"]) * spread_mult * (t ** power)


def shot_chance(c: dict, base: float, distance: float, max_range: float, spread: float,
                side: str = "neutral", bonus: float = 0.0, entity_mod: float = 0.0,
                moving_shooter: bool = False, moving_target: bool = False) -> float:
    """AccuracyHelper.ComputeShotChance (legacy curve kept behind Enabled=false)."""
    hit = c["hit"]
    if max_range <= 0 or distance > max_range * 1.08:
        return 0.0
    distance = min(max(0.0, distance), max_range)
    base = min(max(base, 0.05), 0.99)
    move = 0.0
    if moving_shooter:
        move += hit["MovingShooterPenalty"]
    if moving_target:
        move += hit["MovingTargetPenalty"]

    if not hit["Enabled"]:
        t = distance / max_range
        legacy = base - (t * t) * (0.18 + spread * 0.55) - move + bonus + entity_mod
        return min(max(legacy, 0.08), 0.96)

    chance = (base + bonus + entity_mod) * profile_mult(c, side)
    chance -= distance_penalty(c, distance, max_range, spread) + move
    return min(max(chance, hit["MinChance"]), hit["MaxChance"])


def defense_engage_range(c: dict, weapon_range: float) -> float:
    """CombatRange.GetDefenseEngageRange."""
    base = c["engage"]["defense"]
    return max(base * 0.35, min(base, weapon_range * 1.8))


def enemy_count(c: dict, wave: int) -> int:
    """WaveScaling.EnemyCount."""
    override = c["waves"]["override"]
    if wave in override:
        return int(min(max(override[wave], 1), c["waves"]["cap"]))
    n = c["waves"]["base"] + c["waves"]["growth"] * max(0, wave - 1)
    return int(min(max(n, 1), c["waves"]["cap"]))


def enemy_stats(c: dict, wave: int, difficulty: float = 1.0) -> dict:
    """WaveScaling.EnemyStats."""
    e = c["enemies"]
    w = max(0, wave - 1)
    fire = max(e["min_fire_rate"], e["fire_rate"] * (1 + e["fire_scale"] * w))
    hp_mult = 1 + e["hp_scale"] * w
    dmg_mult = 1 + e["damage_scale"] * w
    if wave > e["era_start"]:
        over = wave - e["era_start"]
        hp_mult *= e["era_hp_growth"] ** over
        dmg_mult *= e["era_damage_growth"] ** over
    return {
        "hp": e["hp"] * hp_mult * difficulty,
        "damage": e["damage"] * dmg_mult * difficulty,
        "fire_rate": fire,
        "accuracy": min(max(e["accuracy"] + e["accuracy_scale"] * w, 0.2), 0.95),
        "armor": e["armor"] + e["armor_scale"] * w,
        "walk_speed": e["walk_speed"] * (1 + e["speed_scale"] * w),
    }


def enemy_weapon(c: dict, weapon_type: str, wave: int) -> dict:
    """EnemyService.getWeaponStats."""
    e = c["enemies"]
    raw = e["weapons"].get(weapon_type) or {}
    growth = min(e["range_growth_cap"], 1 + e["range_growth_per_wave"] * max(0, wave - 1))
    return {
        "damage_mult": raw.get("DamageMult", 1.0),
        "accuracy": raw.get("Accuracy", e["accuracy"]),
        "spread": raw.get("Spread", 0.30),
        "range": raw.get("Range", e["attack_range"]) * growth,
        "fire_rate_mult": raw.get("FireRateMult", 1.0),
    }


def bot_profile(c: dict) -> dict:
    """StatCalculator.BuildCombatStats for a squad profile (defaults: Pistol T1, no upgrades)."""
    b = c["bots"]
    tier = b["weapon_tier"]
    pistol = (c["pistol_tiers"].get(tier) or c["pistol_tiers"].get(1)
              or {"damage": 18.0, "fire_rate": 0.45, "range": 80.0, "accuracy": 0.85, "spread": 0.16})
    reload_mult = max(b["reload_mult"], 0.1)
    accuracy = b["accuracy_override"]
    if accuracy is None:
        accuracy = base_accuracy(pistol["accuracy"], b["upgrade_accuracy"])
    hp = b["hp_override"]
    if hp is None:
        hp = b["hp"]
    return {
        "hp": hp,
        "damage": pistol["damage"] * b["bot_damage_mult"],
        "interval": pistol["fire_rate"] / reload_mult,
        "weapon_range": pistol["range"],
        "range": defense_engage_range(c, pistol["range"]),
        "accuracy": accuracy,
        "spread": pistol["spread"],
        "crit_chance": b["crit_chance"],
        "crit_damage": max(1.5, b["crit_damage"]),
        "count": b["count"],
    }


def hits_to_kill(damage: float, hp: float) -> int:
    return int(math.ceil(hp / damage)) if damage > 0 else 0



# ------------------------------------------------------------- simulation ---

def build_enemy_units(c: dict, wave: int, rng: random.Random, spawn_distance: float) -> list:
    """One unit per EnemyService.SpawnWave spawn slot (weapon rotation + lane)."""
    stats = enemy_stats(c, wave)
    e = c["enemies"]
    rotation = e["weapon_rotation"] or ["Pistol"]
    lane_count = e["lane_count"]
    units = []
    for i in range(enemy_count(c, wave)):
        weapon_type = rotation[i % len(rotation)]
        w = enemy_weapon(c, weapon_type, wave)
        tmod = e["types"].get(weapon_type) or {}
        acc = min(max(w["accuracy"] + tmod.get("AccuracyMod", 0.0)
                      + (stats["accuracy"] - e["accuracy"]), 0.2), 0.95)
        lane = (i % lane_count) + 1
        lateral = ((lane - 1) / max(1, lane_count - 1) - 0.5) * 18.0 * 1.7
        units.append({
            "id": "E%d" % (i + 1),
            "type": weapon_type,
            "lane": lane,
            "hp": stats["hp"] * tmod.get("HPMult", 1.0),
            "damage": e["damage"] * w["damage_mult"] * (stats["damage"] / e["damage"]),
            "interval": max(e["min_fire_rate"], stats["fire_rate"] * w["fire_rate_mult"]),
            "accuracy": acc,
            "spread": w["spread"],
            "range": w["range"],
            "speed": stats["walk_speed"] * tmod.get("SpeedMult", 1.0) * rng.uniform(0.85, 1.15),
            "lateral": lateral,
            "dist": spawn_distance,
            "spawn_at": 0.0,
            "alive": True,
            "state": "Moving",
            "slot": None,
            "last_fire": 0.0,
        })
    return units


def _spawn_times(c: dict, count: int) -> list:
    """GameConfig.Battle pacing: EnemySpawnInterval, EnemyGroupSize, EnemyGroupGap."""
    w = c["waves"]
    out = []
    t = 0.0
    for i in range(count):
        out.append(t)
        t += w["spawn_interval"]
        if (i + 1) % w["group_size"] == 0:
            t += w["group_gap"]
    return out



def run_wave(c: dict, wave: int, rng: random.Random, spawn_distance: float = SPAWN_DISTANCE,
             bot_spread: float = BOT_SPREAD) -> dict:
    """One wave, deterministic per rng. Mirrors the BotService/EnemyService tick loop."""
    hero = bot_profile(c)
    e_cfg = c["enemies"]
    downed_cfg = c["downed"]
    units = build_enemy_units(c, wave, rng, spawn_distance)
    for unit, st in zip(units, _spawn_times(c, len(units))):
        unit["spawn_at"] = st

    bots = []
    for i in range(hero["count"]):
        bots.append({
            "id": "Bot_%d" % (i + 1),
            "hp": hero["hp"],
            "max_hp": hero["hp"],
            "downed": False,
            "down_at": None,
            "revived": 0,
            "lateral": (i - (hero["count"] - 1) / 2.0) * bot_spread,
            "next_fire": rng.uniform(0.0, hero["interval"]),
            "target": None,
        })

    max_attackers = min(e_cfg["max_attackers"], e_cfg["lane_count"] * e_cfg["slots_per_lane"])
    lane_taken = {}
    kills = bot_shots = bot_hits = 0
    enemy_shots = enemy_hits = enemy_melee = 0
    dmg_to_bots = 0.0
    down_events = 0
    t = 0.0
    end_reason = "timeout"

    while t < SIM_TIMEOUT:
        t += SIM_DT
        spawned = [u for u in units if u["alive"] and u["spawn_at"] <= t]

        # ---- bots shoot (BotService loop, one shot per FireRate) ----
        standing = [b for b in bots if not b["downed"]]
        focus = {}
        for b in standing:
            if b["target"] and b["target"]["alive"]:
                focus[b["target"]["id"]] = focus.get(b["target"]["id"], 0) + 1
        for b in standing:
            if t < b["next_fire"]:
                continue
            b["next_fire"] = t + hero["interval"]
            pool = []
            for u in spawned:
                d = math.hypot(u["dist"], u["lateral"] - b["lateral"])
                if d <= hero["range"]:
                    pool.append((d, u))
            if not pool:
                b["target"] = None
                continue
            pool.sort(key=lambda pair: pair[0])
            pool = pool[:8]
            pick = None
            if b["target"] and b["target"]["alive"] and any(u is b["target"] for _, u in pool):
                if focus.get(b["target"]["id"], 0) < 2 and rng.random() < 0.62:
                    pick = b["target"]
            if pick is None:
                weights = []
                total = 0.0
                for d, u in pool:
                    f = focus.get(u["id"], 0)
                    w = (1.0 / (1.0 + d * 0.035)) / (1.0 + f * f)
                    if f >= 2:
                        w *= 0.1
                    elif f >= 1:
                        w *= 0.5
                    weights.append(w)
                    total += w
                pick = pool[-1][1]
                if total > 0:
                    roll = rng.random() * total
                    acc = 0.0
                    for (d, u), w in zip(pool, weights):
                        acc += w
                        if roll <= acc:
                            pick = u
                            break
            b["target"] = pick
            dist = min(math.hypot(pick["dist"], pick["lateral"] - b["lateral"]), hero["range"])
            chance = shot_chance(c, hero["accuracy"], dist, hero["range"], hero["spread"],
                                 side="bot", moving_target=pick["state"] == "Moving")
            bot_shots += 1
            if rng.random() <= chance:
                bot_hits += 1
                dmg = hero["damage"]
                if rng.random() < hero["crit_chance"]:
                    dmg *= hero["crit_damage"]
                pick["hp"] -= dmg
                if pick["hp"] <= 0:
                    pick["alive"] = False
                    kills += 1
                    if pick["slot"] is not None:
                        lane_taken.pop(pick["slot"], None)

        # ---- enemies advance + claim melee slots (EnemyService.updateEnemy) ----
        gate = e_cfg["melee_range"]
        standoff = e_cfg["attack_spacing"]
        for u in units:
            if not u["alive"] or u["spawn_at"] > t:
                continue
            if u["slot"] is None and u["state"] != "Queued" and u["dist"] <= gate:
                if len(lane_taken) < max_attackers and u["lane"] not in lane_taken:
                    lane_taken[u["lane"]] = u["id"]
                    u["slot"] = u["lane"]
                else:
                    u["state"] = "Queued"
            if u["state"] == "Queued":
                u["dist"] = max(gate, u["dist"] - u["speed"] * SIM_DT)
                continue
            u["dist"] = max(standoff, u["dist"] - u["speed"] * SIM_DT)
            u["state"] = "Attacking" if (u["slot"] is not None and u["dist"] <= standoff + 0.01) else "Moving"

        # ---- enemies shoot: melee is guaranteed, ranged uses the accuracy curve ----
        for u in units:
            if not u["alive"] or u["spawn_at"] > t or u["state"] == "Queued":
                continue
            standing = [b for b in bots if not b["downed"]]
            if not standing:
                break
            target = min(standing, key=lambda b: math.hypot(u["dist"], u["lateral"] - b["lateral"]))
            d = math.hypot(u["dist"], u["lateral"] - target["lateral"])
            melee_reach = e_cfg["attack_arrive"] + MELEE_SEARCH_BONUS
            attacking = u["state"] == "Attacking"
            melee = attacking and d <= melee_reach
            if attacking and not melee:
                # EnemyService: the melee branch only searches (arrive + 8) studs around
                # the enemy root, so an attacker with no bot that close holds fire.
                continue
            interval = e_cfg["melee_fire_rate"] if melee else u["interval"]
            if t - u["last_fire"] < interval:
                continue
            if melee:
                u["last_fire"] = t
                enemy_melee += 1
                dmg = u["damage"] * e_cfg["melee_damage_mult"]
            else:
                if d > u["range"]:
                    continue
                u["last_fire"] = t
                chance = shot_chance(c, u["accuracy"], min(d, u["range"]), u["range"], u["spread"],
                                     side="enemy", moving_shooter=u["state"] == "Moving")
                enemy_shots += 1
                if rng.random() > chance:
                    continue
                dmg = u["damage"]
            enemy_hits += 1
            dmg_to_bots += dmg
            target["hp"] -= dmg
            if target["hp"] <= 0 and not target["downed"]:
                target["downed"] = True
                down_events += 1
                if downed_cfg["enabled"]:
                    target["hp"] = 0.0
                    target["down_at"] = t

        # ---- downed bots revive (BotService.ReviveBot loop) ----
        if downed_cfg["enabled"] and downed_cfg["revive_delay"] > 0:
            for b in bots:
                if b["downed"] and b["down_at"] is not None and t - b["down_at"] >= downed_cfg["revive_delay"]:
                    b["downed"] = False
                    b["down_at"] = None
                    b["hp"] = b["max_hp"] * downed_cfg["revive_hp_percent"]
                    b["revived"] += 1
                    b["target"] = None

        alive_units = [u for u in units if u["alive"]]
        pending = [u for u in units if u["spawn_at"] > t]
        if not alive_units and not pending:
            end_reason = "cleared"
            break
        if not any(not b["downed"] for b in bots):
            # WaveService.OnDefenderDied -> OnWipe: no standing defender left
            end_reason = "wipe"
            break

    alive_units = [u for u in units if u["alive"]]
    standing = [b for b in bots if not b["downed"]]
    return {
        "wave": wave,
        "enemies": len(units),
        "kills": kills,
        "end": end_reason,
        "cleared": end_reason == "cleared",
        "wiped": end_reason == "wipe",
        "time": round(t, 1),
        "enemies_left": len(alive_units),
        "bots_standing": len(standing),
        "bot_downs": down_events,
        "bot_revives": sum(b["revived"] for b in bots),
        "bot_hp_total": round(sum(max(0.0, b["hp"]) for b in bots), 1),
        "bot_hp_max": round(hero["hp"] * len(bots), 1),
        "damage_to_bots": round(dmg_to_bots, 1),
        "bot_shots": bot_shots,
        "bot_hits": bot_hits,
        "enemy_shots": enemy_shots,
        "enemy_hits": enemy_hits,
        "enemy_melee_hits": enemy_melee,
        "bot_hit_rate": (bot_hits / bot_shots) if bot_shots else 0.0,
        "enemy_hit_rate": (enemy_hits / (enemy_shots + enemy_melee))
                          if (enemy_shots + enemy_melee) else 0.0,
        "enemy_ranged_hit_rate": ((enemy_hits - enemy_melee) / enemy_shots) if enemy_shots else 0.0,
    }


def run_waves(c: dict, waves, trials: int, seed: int, spawn_distance: float,
              bot_spread: float = BOT_SPREAD) -> list:
    """Aggregate `trials` runs per wave."""
    rng = random.Random(seed)
    out = []
    for wave in waves:
        runs = [run_wave(c, wave, rng, spawn_distance, bot_spread) for _ in range(trials)]
        cleared = [r for r in runs if r["cleared"]]
        out.append({
            "wave": wave,
            "enemies": runs[0]["enemies"],
            "trials": trials,
            "clear_rate": len(cleared) / trials,
            "avg_time": (sum(r["time"] for r in cleared) / len(cleared)) if cleared else 0.0,
            "avg_kills": sum(r["kills"] for r in runs) / trials,
            "avg_hp_left_pct": (sum(r["bot_hp_total"] / r["bot_hp_max"] for r in cleared)
                                / len(cleared)) if cleared else 0.0,
            "down_rate": sum(1 for r in runs if r["bot_downs"] > 0) / trials,
            "avg_downs": sum(r["bot_downs"] for r in runs) / trials,
            "avg_revives": sum(r["bot_revives"] for r in runs) / trials,
            "avg_dmg_to_bots": sum(r["damage_to_bots"] for r in runs) / trials,
            "bot_hit_rate": sum(r["bot_hits"] for r in runs) / max(1, sum(r["bot_shots"] for r in runs)),
            "enemy_hit_rate": (sum(r["enemy_hits"] for r in runs)
                               / max(1, sum(r["enemy_shots"] + r["enemy_melee_hits"] for r in runs))),
            "enemy_ranged_hit_rate": (sum(r["enemy_hits"] - r["enemy_melee_hits"] for r in runs)
                                      / max(1, sum(r["enemy_shots"] for r in runs))),
            "enemy_melee_share": (sum(r["enemy_melee_hits"] for r in runs)
                                  / max(1, sum(r["enemy_hits"] for r in runs))),
        })
    return out



# -------------------------------------------------------------- reporting ---

WIRING = [
    ("src/Server/Services/BotService.lua",
     ["Downed", "DownBot", "ReviveBot", 'GetProfileMult("bot")']),
    ("src/Server/Services/EnemyService.lua",
     ['GetProfileMult("enemy")', "EnemyWeapons", "DamageMult", "FireRateMult"]),
    ("src/Server/Services/WaveService.lua",
     ["anyBotStanding", "BotsDowned"]),
    ("src/Shared/Builders/CharacterRigBuilder.lua",
     ["DownedPose", "ClearDownedPose"]),
    ("src/Shared/Util/AccuracyHelper.lua",
     ["DistancePenalty", "GetProfileMult", "profileMult"]),
]


def pct(value: float, digits: int = 1) -> str:
    return ("%." + str(digits) + "f%%") % (value * 100.0)


def check(checks: list, ok: bool, text: str, hard: bool = True) -> None:
    checks.append({"ok": bool(ok), "hard": bool(hard), "text": text})


def report_config(c: dict, lines: list, checks: list) -> None:
    hit = c["hit"]
    lines.append("-- Shooting model (GameConfig.Battle.HitChance) ---------------")
    lines.append("curve enabled=%s   bot profile=%.2f   enemy profile=%.2f"
                 % (hit["Enabled"], profile_mult(c, "bot"), profile_mult(c, "enemy")))
    lines.append("distance penalty: starts at %.0f%% of max range, power %.2f, max %.2f"
                 % (hit["NearFalloffStart"] * 100, hit["FalloffPower"], hit["MaxDistancePenalty"]))
    lines.append("spread: base %.2f + spread * %.2f   moving shooter -%.2f, moving target -%.2f"
                 % (hit["SpreadBase"], hit["SpreadWeight"],
                    hit["MovingShooterPenalty"], hit["MovingTargetPenalty"]))
    bot = bot_profile(c)
    lines.append("bots: %d x HP %.0f, Pistol T%d %.0f dmg every %.2fs, engage %.0f studs, acc %.3f, spread %.2f"
                 % (bot["count"], bot["hp"], c["bots"]["weapon_tier"], bot["damage"], bot["interval"],
                    bot["range"], bot["accuracy"], bot["spread"]))
    e = c["enemies"]
    lines.append("enemies: own weapons (EnemiesConfig.EnemyWeapons), base %.0f dmg / %.2fs / acc %.2f"
                 % (e["damage"], e["fire_rate"], e["accuracy"]))
    lines.append("melee: max %d attackers (%d lanes), %.0f dmg x%.2f every %.2fs, downed bots ignored"
                 % (min(e["max_attackers"], e["lane_count"] * e["slots_per_lane"]),
                    e["lane_count"], e["damage"], e["melee_damage_mult"], e["melee_fire_rate"]))
    d = c["downed"]
    lines.append("downed: enabled=%s revive after %.0fs at %.0f%% HP (revive on wave start: %s)"
                 % (d["enabled"], d["revive_delay"], d["revive_hp_percent"] * 100,
                    d["revive_on_wave_start"]))
    lines.append("")

    check(checks, hit["Enabled"], "HitChance curve is the active model (Enabled=true)")
    check(checks, not c["force_hits"]["bot"] and not c["force_hits"]["enemy"],
          "debug force-hit flags are OFF (ForceBotHitsForTest/ForceEnemyHitsForTest = false)")
    check(checks, d["enabled"] and d["revive_delay"] > 0,
          "downed instead-of-death is configured (Enabled, ReviveDelaySec > 0)")
    check(checks, profile_mult(c, "bot") > profile_mult(c, "enemy"),
          "bot accuracy profile beats the enemy profile (%.2f > %.2f)"
          % (profile_mult(c, "bot"), profile_mult(c, "enemy")))


def report_chance_table(c: dict, lines: list, checks: list) -> None:
    """Same distance, both sides: bot Pistol T1 vs enemy Pistol (their own gun)."""
    bot = bot_profile(c)
    w = enemy_weapon(c, "Pistol", 1)
    tmod = c["enemies"]["types"].get("Pistol") or {}
    stats = enemy_stats(c, 1)
    enemy_acc = min(max(w["accuracy"] + tmod.get("AccuracyMod", 0.0)
                        + (stats["accuracy"] - c["enemies"]["accuracy"]), 0.2), 0.95)
    lines.append("-- Hit chance at the same distance (wave 1) ------------------")
    lines.append("  bot:   Pistol T%d, acc %.3f, spread %.2f, maxRange %.0f (target moving)"
                 % (c["bots"]["weapon_tier"], bot["accuracy"], bot["spread"], bot["range"]))
    lines.append("  enemy: Pistol,    acc %.3f, spread %.2f, maxRange %.0f (shooter moving)"
                 % (enemy_acc, w["spread"], w["range"]))
    lines.append("  dist      bot    enemy    delta")
    worst = 1.0
    for dist in (10, 20, 40, 60, 90, 120, 144):
        b = shot_chance(c, bot["accuracy"], dist, bot["range"], bot["spread"],
                        side="bot", moving_target=True)
        e = shot_chance(c, enemy_acc, dist, w["range"], w["spread"],
                        side="enemy", moving_shooter=True)
        worst = min(worst, b - e)
        lines.append("  %4d   %6.3f   %6.3f  %+6.3f" % (dist, b, e, b - e))
    lines.append("")
    close = shot_chance(c, bot["accuracy"], 10, bot["range"], bot["spread"],
                        side="bot", moving_target=True)
    far_enemy = shot_chance(c, enemy_acc, w["range"], w["range"], w["spread"],
                            side="enemy", moving_shooter=True)
    check(checks, worst > 0.0,
          "bots outshoot enemies at every tested distance (worst delta %+.3f)" % worst)
    check(checks, close > 0.6, "close-range bot shots are reliable (%.3f at 10 studs)" % close,
          hard=False)
    check(checks, far_enemy <= 0.15,
          "enemy shots at their own max range barely land (%.3f)" % far_enemy, hard=False)


def report_hits_to_kill(c: dict, lines: list, checks: list) -> None:
    bot = bot_profile(c)
    e = c["enemies"]
    b = c["bots"]
    # the 6-hit target is defined for the stock squad (Pistol T1, no overrides)
    stock = (b["weapon_tier"] == 1 and b.get("accuracy_override") is None
             and b.get("hp_override") is None)
    tier = b["weapon_tier"]
    lines.append("-- Shots to kill (bot Pistol T%d = %.0f dmg) -------------------" % (tier, bot["damage"]))
    lines.append("  wave  enemy       HP    hits")
    wave1_counts = []
    for wave in (1, 10):
        stats = enemy_stats(c, wave)
        for weapon_type in e["weapon_rotation"]:
            tmod = e["types"].get(weapon_type) or {}
            hp = stats["hp"] * tmod.get("HPMult", 1.0)
            n = hits_to_kill(bot["damage"], hp)
            lines.append("  %4d  %-9s %5.0f  %5d" % (wave, weapon_type, hp, n))
            if wave == 1:
                wave1_counts.append(n)
        lines.append("")
    avg = sum(wave1_counts) / len(wave1_counts)
    plain_hp = enemy_stats(c, 1)["hp"]
    lines.append("  wave 1 average: %.1f hits to kill (range %d-%d)" % (avg, min(wave1_counts),
                                                                    max(wave1_counts)))
    if not stock:
        lines.append("  (Pistol T%d squad - the ~6 hits to kill target applies to a stock Pistol T1 squad)"
                     % tier)
    lines.append("")
    note = "" if stock else " [informational: stock Pistol T1 target]"
    check(checks, 5 <= avg <= 7, "wave 1 enemies die in ~6 hits (avg %.1f)%s" % (avg, note),
          hard=stock)
    check(checks, hits_to_kill(bot["damage"], plain_hp) == 6,
          "a base wave 1 enemy (HP %.0f, no type multiplier) takes exactly 6 hits%s" % (plain_hp, note),
          hard=stock)
    check(checks, max(wave1_counts) <= 8,
          "no wave 1 enemy type needs more than 8 hits (worst %d)%s" % (max(wave1_counts), note),
          hard=stock)


def report_wiring(lines: list, checks: list) -> None:
    lines.append("-- Source wiring (guards against silent regressions) ----------")
    for path, needles in WIRING:
        text = read(path)
        missing = [n for n in needles if n not in text]
        lines.append("  %-46s %s" % (path.replace("src/", ""),
                                     "OK" if not missing else "MISSING " + ", ".join(missing)))
        check(checks, not missing,
              "%s still references %s" % (path.replace("src/", ""), ", ".join(needles)))
    legacy = []
    for path, needles in (
        ("src/Server/Services/EnemyService.lua", ["waveFireMult", "weaponCfg.Damage ", "weaponCfg.FireRate "]),
        ("src/Server/Services/BotService.lua", ["ForceBotHitsForTest = true"]),
    ):
        text = read(path)
        legacy += ["%s: %s" % (path.replace("src/", ""), n.strip()) for n in needles if n in text]
    lines.append("  %-46s %s" % ("legacy refs", "OK" if not legacy else "FOUND " + "; ".join(legacy)))
    check(checks, not legacy, "no legacy combat references left (%s)" % ("; ".join(legacy) or "none"))
    lines.append("")


def find_lune() -> str | None:
    """Lune ships in %USERPROFILE%\\.local\\bin via install-tools.ps1."""
    exe = shutil.which("lune")
    if exe:
        return exe
    local = Path.home() / ".local" / "bin" / ("lune.exe" if sys.platform == "win32" else "lune")
    return str(local) if local.is_file() else None


def run_luau_lint(target: str = "src") -> dict:
    """Syntax-check every .lua module with Lune's embedded Luau compiler.

    `luau.load` compiles without executing, so this proves the edited services
    (EnemyService/BotService/AccuracyHelper/...) parse as Luau even though Studio
    is the only place they can actually run.
    """
    script = ROOT / "tools" / "lint_luau.luau"
    lune = find_lune()
    if lune is None:
        return {"ok": False, "skipped": True,
                "output": "lune not found - run .\\install-tools.ps1 (https://lune-org docs)"}
    if not script.is_file():
        return {"ok": False, "skipped": True, "output": "tools/lint_luau.luau is missing"}
    try:
        proc = subprocess.run([lune, "run", str(script), target], cwd=str(ROOT),
                              capture_output=True, text=True, timeout=180)
    except Exception as exc:  # noqa: BLE001 - report any spawn failure as a skip
        return {"ok": False, "skipped": True, "output": "lune failed to start: %s" % exc}
    out = (proc.stdout + proc.stderr).strip()
    return {"ok": proc.returncode == 0, "skipped": False, "output": out}


def report_lint(lint: dict, lines: list, checks: list) -> None:
    lines.append("-- Luau syntax check (lune run tools/lint_luau.luau) ----------")
    if lint.get("skipped"):
        lines.append("  skipped: %s" % lint["output"])
        lines.append("")
        return
    out_lines = [ln for ln in lint["output"].splitlines() if ln.strip()]
    summary = out_lines[-1] if out_lines else "(no output)"
    lines.append("  %s" % summary)
    for ln in out_lines:
        if ln.startswith("FAIL"):
            lines.append("  %s" % ln)
    lines.append("")
    check(checks, lint["ok"], "every module under src/ parses as Luau (%s)" % summary)


def report_sim(c: dict, waves: list, lines: list, checks: list, squad: str = "",
               safe_waves: int = 3) -> list:
    """Print one simulation table plus its checks.

    `safe_waves` = waves that a squad with this loadout must clear outright;
    later waves only warn for the baseline squad (see main()).
    """
    trials = waves[0]["trials"] if waves else 0
    lines.append("-- Wave simulation: %s (%d trials/wave) ---------------" % (squad or "squad", trials))
    lines.append("  wave  enemies  cleared   time   hp left  downs  revives   dmg taken   bot acc  enemy acc")
    for r in waves:
        lines.append("  %4d  %7d  %6.1f%%  %5.1fs  %6.1f%%  %5.2f  %7.2f  %9.1f  %7.1f%%  %9.1f%%"
                     % (r["wave"], r["enemies"], r["clear_rate"] * 100, r["avg_time"],
                        r["avg_hp_left_pct"] * 100, r["avg_downs"], r["avg_revives"],
                        r["avg_dmg_to_bots"], r["bot_hit_rate"] * 100, r["enemy_hit_rate"] * 100))
    lines.append("")
    bot_rate = sum(r["bot_hit_rate"] * r["enemies"] for r in waves) / max(1, sum(r["enemies"] for r in waves))
    enemy_rate = sum(r["enemy_hit_rate"] * r["enemies"] for r in waves) / max(1, sum(r["enemies"] for r in waves))
    check(checks, bot_rate > enemy_rate,
          "bots land more shots than enemies over waves %s (%s vs %s)"
          % (",".join(str(r["wave"]) for r in waves), pct(bot_rate), pct(enemy_rate)))
    for r in waves:
        if r["wave"] <= safe_waves:
            check(checks, r["clear_rate"] >= 0.9,
                  "wave %d is winnable (%s clear rate %s)" % (r["wave"], squad or "squad",
                                                              pct(r["clear_rate"])))
        else:
            check(checks, r["clear_rate"] >= 0.9,
                  "wave %d is winnable with %s (clear rate %s)"
                  % (r["wave"], squad or "squad", pct(r["clear_rate"])),
                  hard=False)
    tension = [r for r in waves if r["wave"] >= 3]
    if tension:
        hurts = any(r["down_rate"] > 0.05 or r["avg_dmg_to_bots"] > 0 for r in tension)
        check(checks, hurts, "%s: waves 3-5 actually pressure the squad (damage / downs)"
              % (squad or "squad"), hard=False)
        squad_hp = max(1.0, c["bots"]["hp"] * c["bots"]["count"])
        costs = [(r["avg_dmg_to_bots"] / squad_hp, r["wave"]) for r in tension]
        worst_cost, worst_wave = max(costs)
        check(checks, worst_cost >= 0.2,
              "%s: waves 3-5 cost real HP (wave %d took %s of squad HP)"
              % (squad or "squad", worst_wave, pct(worst_cost)), hard=False)
    return [{"bot_hit_rate": bot_rate, "enemy_hit_rate": enemy_rate}]


def report_assumptions(c: dict, lines: list, spawn_distance: float, bot_spread: float,
                       trials: int, skip_progression: bool = False) -> None:
    e = c["enemies"]
    u = c["upgrades"]
    lines.append("-- Simulation assumptions -------------------------------------")
    lines.append("  enemies spawn %.0f studs out, walk straight down their lane; squad holds the line"
                 % spawn_distance)
    lines.append("  squad = %d bots %.1f studs apart, Pistol T%s, no XP upgrades unless overridden"
                 % (c["bots"]["count"], bot_spread, c["bots"]["weapon_tier"]))
    lines.append("  bots spread fire (BotService focus weights); enemies always shoot the nearest bot")
    lines.append("  melee gate (EnemiesConfig.AttackArriveDistance %.1f + 8 stud search radius, EnemyService l.545):"
                 % e["attack_arrive"])
    lines.append("    an attacker only lands melee/damage while a bot is within %.1f studs of it"
                 % (e["attack_arrive"] + MELEE_SEARCH_BONUS))
    lines.append("  a wave is lost only when every bot is down at the same moment (WaveService.OnWipe)")
    lines.append("  %d seeded trials per wave - same seed always prints the same numbers" % trials)
    if skip_progression:
        lines.append("  progression table disabled (--no-progression / explicit squad overrides)")
    else:
        lines.append("  second table = same squad after spending wave 1-4 XP: HP %.0f -> %.0f,"
                     % (u["base"]["HP"], u["base"]["HP"] + u["per_level"]["HP"] * PROGRESSION_HP_LEVELS))
        lines.append("    accuracy %.2f -> %.2f (%d HP levels + %d Accuracy levels, ~200 XP)"
                     % (u["base"]["Accuracy"],
                        u["base"]["Accuracy"] + u["per_level"]["Accuracy"] * PROGRESSION_ACCURACY_LEVELS,
                        PROGRESSION_HP_LEVELS, PROGRESSION_ACCURACY_LEVELS))
    lines.append("")


def report_hints(c: dict, waves: list, lines: list) -> None:
    """Concrete knobs for any wave that does not reliably clear."""
    weak = [r for r in waves if r["clear_rate"] < 0.9]
    if not weak:
        return
    e = c["enemies"]
    d = c["downed"]
    dps = e["damage"] * e["melee_damage_mult"] / max(0.05, e["melee_fire_rate"])
    attackers = min(e["max_attackers"], e["lane_count"] * e["slots_per_lane"])
    lines.append("-- Tuning hints (waves below 90% clear) -----------------------")
    lines.append("  affected waves: %s" % ", ".join(str(r["wave"]) for r in weak))
    lines.append("  %d simultaneous attackers x %.1f dps each = %.0f dps of unmissable point-blank damage"
                 % (attackers, dps, attackers * dps))
    lines.append("  a squad of %d x %.0f HP survives %.1fs of that focus fire"
                 % (c["bots"]["count"], c["bots"]["hp"],
                    c["bots"]["count"] * c["bots"]["hp"] / max(1.0, attackers * dps)))
    lines.append("  least invasive knobs first:")
    lines.append("    EnemiesConfig.MeleeDamageMult  %.2f -> %.2f" % (e["melee_damage_mult"],
                                                                     round(e["melee_damage_mult"] * 0.8, 2)))
    lines.append("    EnemiesConfig.MeleeFireRate    %.2f -> %.2f" % (e["melee_fire_rate"],
                                                                     round(e["melee_fire_rate"] * 1.25, 2)))
    lines.append("    EnemiesConfig.MaxAttackers     %d -> %d" % (e["max_attackers"],
                                                                  max(1, e["max_attackers"] - 1)))
    lines.append("    GameConfig.Downed.ReviveDelaySec %.0f -> %.0f" % (d["revive_delay"],
                                                                       max(3.0, d["revive_delay"] * 0.7)))
    lines.append("    (EnemiesConfig.BaseStats.HP/PerWaveScaling.HP also feed enemy survivability)")
    lines.append("  or keep it and assume upgrades: --weapon-tier 2..5 / --bot-accuracy / --bot-hp")
    lines.append("")


ROLL_RE = re.compile(
    r"(BOT|ENEMY)_HIT_ROLL .*?distance=([\d.]+) .*?range=([\d.]+) .*?accuracy=([-\d.]+) "
    r".*?chance=([\d.]+) .*?roll=([\d.]+) .*?los=(\w+) .*?hit=(\w+)"
)


def parse_log(path: str) -> dict:
    """Real telemetry: BOT_HIT_ROLL / ENEMY_HIT_ROLL lines from logs/game.log.

    Lines with `los=false` are not shots - the shooter never rolled (chance=0 by
    design when the raycast is blocked), so they are counted separately.
    """
    if not Path(path).is_file():
        return {"error": "file not found: %s" % path}
    sides = {"BOT": {"shots": 0, "hits": 0, "chance_sum": 0.0, "blocked": 0},
             "ENEMY": {"shots": 0, "hits": 0, "chance_sum": 0.0, "blocked": 0}}
    downs = revives = 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "Defender downed" in line or "BOT_DOWNED" in line:
                downs += 1
            elif "BOT_REVIVED" in line:
                revives += 1
            if "HIT_ROLL" not in line:
                continue
            m = ROLL_RE.search(line)
            if not m:
                continue
            side, _dist, _rng, _acc, chance, _roll, los, hit = m.groups()
            bucket = sides[side]
            if los.lower() != "true":
                bucket["blocked"] += 1
                continue
            bucket["shots"] += 1
            bucket["chance_sum"] += float(chance)
            if hit.lower() == "true":
                bucket["hits"] += 1
    out = {"path": path, "downs": downs, "revives": revives}
    for side, bucket in sides.items():
        shots = bucket["shots"]
        out[side.lower()] = {
            "shots": shots,
            "hits": bucket["hits"],
            "hit_rate": (bucket["hits"] / shots) if shots else 0.0,
            "expected": (bucket["chance_sum"] / shots) if shots else 0.0,
            "blocked": bucket["blocked"],
        }
    return out


def report_telemetry(t: dict, lines: list, checks: list) -> None:
    lines.append("-- Live telemetry (%s) -----------------" % t.get("path", "?"))
    if "error" in t:
        lines.append("  %s" % t["error"])
        lines.append("")
        return
    for side in ("bot", "enemy"):
        s = t[side]
        if not s["shots"] and not s["blocked"]:
            continue
        lines.append("  %-5s shots=%-5d hits=%-5d observed=%5.1f%%  expected=%5.1f%%  (LOS blocked: %d)"
                     % (side, s["shots"], s["hits"], s["hit_rate"] * 100,
                        s["expected"] * 100, s["blocked"]))
    lines.append("  downed events=%d  revives=%d" % (t["downs"], t["revives"]))
    if not t["bot"]["shots"] and not t["enemy"]["shots"]:
        lines.append("  no usable hit rolls: set GameConfig.Battle.DebugCombatDamage = true, play a wave,")
        lines.append("  and make sure CombatVFX.HasClearLos returns true (every logged roll was blocked)")
    lines.append("")
    if t["bot"]["shots"] >= 30 and t["enemy"]["shots"] >= 30:
        check(checks, t["bot"]["hit_rate"] > t["enemy"]["hit_rate"],
              "live telemetry: bots hit more often than enemies (%.1f%% vs %.1f%%, n=%d/%d)"
              % (t["bot"]["hit_rate"] * 100, t["enemy"]["hit_rate"] * 100,
                 t["bot"]["shots"], t["enemy"]["shots"]))


def print_checks(checks: list) -> None:
    hard = [c for c in checks if c["hard"]]
    failed = [c for c in checks if not c["ok"]]
    soft = [c for c in failed if not c["hard"]]
    print("-- Checks ----------------------------------------------------")
    for c in checks:
        if c["ok"]:
            print("  [ok]   %s" % c["text"])
        else:
            print("  [%s] %s" % ("FAIL" if c["hard"] else "warn", c["text"]))
    print("")
    print("  hard checks: %d/%d passed" % (len(hard) - len([c for c in hard if not c["ok"]]), len(hard)))
    if soft:
        print("  %d soft warning(s)" % len(soft))
    verdict = "PASS" if not [c for c in hard if not c["ok"]] else "FAIL"
    print("  verdict: %s" % verdict)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--waves", default="1,2,3,4,5", help="comma separated wave numbers")
    ap.add_argument("--trials", type=int, default=60, help="simulation runs per wave")
    ap.add_argument("--seed", type=int, default=1337, help="RNG seed (results are reproducible)")
    ap.add_argument("--spawn-distance", type=float, default=SPAWN_DISTANCE,
                    help="enemy distance from the defense line at spawn (studs)")
    ap.add_argument("--bot-spread", type=float, default=BOT_SPREAD,
                    help="lateral gap between squad members on the defense line (studs)")
    ap.add_argument("--weapon-tier", type=int, default=1, choices=(1, 2, 3, 4, 5),
                    help="pistol tier the squad starts with")
    ap.add_argument("--bot-accuracy", type=float, default=None,
                    help="override the computed bot accuracy (0.35-0.95)")
    ap.add_argument("--bot-hp", type=float, default=None,
                    help="override squad HP per bot (default: UpgradesConfig HP base)")
    ap.add_argument("--log", default=None, help="parse real BOT_HIT_ROLL telemetry from a log file")
    ap.add_argument("--lint", action="store_true",
                    help="also syntax-check every src/ module with lune (tools/lint_luau.luau)")
    ap.add_argument("--no-progression", action="store_true",
                    help="skip the second table for a squad that spent its wave 1-4 XP")
    ap.add_argument("--check", action="store_true", help="exit 1 when a hard check fails")
    ap.add_argument("--json", action="store_true", help="machine readable output")
    ap.add_argument("--quiet", action="store_true", help="only print the checks")
    args = ap.parse_args(argv)

    wave_list = []
    for chunk in str(args.waves).split(","):
        chunk = chunk.strip()
        if chunk:
            wave_list.append(int(chunk))
    if not wave_list:
        ap.error("--waves must list at least one wave")

    c = parse_all()
    c["bots"]["weapon_tier"] = args.weapon_tier
    if args.bot_accuracy is not None:
        c["bots"]["accuracy_override"] = min(max(args.bot_accuracy, 0.05), 0.99)
    if args.bot_hp is not None:
        c["bots"]["hp_override"] = max(1.0, args.bot_hp)
    squad_overridden = args.bot_accuracy is not None or args.bot_hp is not None

    lines: list = []
    checks: list = []
    sims = []

    lines.append("=== Bridge Defense - first waves combat validation ===")
    lines.append("")
    report_config(c, lines, checks)
    report_chance_table(c, lines, checks)
    report_hits_to_kill(c, lines, checks)
    report_assumptions(c, lines, args.spawn_distance, args.bot_spread, args.trials,
                       squad_overridden or args.no_progression)

    baseline = run_waves(c, wave_list, args.trials, args.seed, args.spawn_distance, args.bot_spread)
    sims.append({"squad": "no XP upgrades", "waves": baseline})
    report_sim(c, baseline, lines, checks, "no XP upgrades", safe_waves=3)
    report_hints(c, baseline, lines)

    if not (args.no_progression or squad_overridden):
        up = parse_all()
        up["bots"]["weapon_tier"] = args.weapon_tier
        base = up["upgrades"]["base"]
        per_level = up["upgrades"]["per_level"]
        up["bots"]["hp"] = base["HP"] + per_level["HP"] * PROGRESSION_HP_LEVELS
        up["bots"]["upgrade_accuracy"] = (base["Accuracy"]
                                          + per_level["Accuracy"] * PROGRESSION_ACCURACY_LEVELS)
        veteran = run_waves(up, wave_list, args.trials, args.seed, args.spawn_distance, args.bot_spread)
        sims.append({"squad": "wave 1-4 XP spent", "waves": veteran})
        report_sim(up, veteran, lines, checks, "wave 1-4 XP spent", safe_waves=5)

    report_wiring(lines, checks)
    lint = run_luau_lint() if args.lint else None
    if lint is not None:
        report_lint(lint, lines, checks)
    telemetry = parse_log(args.log) if args.log else None
    if telemetry is not None:
        report_telemetry(telemetry, lines, checks)

    hard_failed = [ck for ck in checks if ck["hard"] and not ck["ok"]]

    if args.json:
        print(json.dumps({
            "hit_chance": c["hit"],
            "force_hits": c["force_hits"],
            "downed": c["downed"],
            "sims": sims,
            "checks": checks,
            "lint": lint,
            "telemetry": telemetry,
        }, indent=2))
    else:
        if not args.quiet:
            print("\n".join(lines))
        print_checks(checks)

    return 1 if (args.check and hard_failed) else 0


if __name__ == "__main__":
    sys.exit(main())

