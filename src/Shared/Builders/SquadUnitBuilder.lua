local CharacterRigBuilder = require(script.Parent.CharacterRigBuilder)

local SquadUnitBuilder = {}

function SquadUnitBuilder.CreateDefenderModel(opts)
	return CharacterRigBuilder.CreateNPC({
		SlotIndex = opts.SlotIndex,
		Position = opts.Position,
		FacingCFrame = opts.FacingCFrame,
		DisplayName = opts.DisplayName,
		WeaponType = opts.WeaponType,
		WeaponTier = opts.WeaponTier,
		CurrentHP = opts.CurrentHP,
		MaxHP = opts.MaxHP,
		IsBot = opts.IsBot,
		Team = "Ally",
		ModelName = opts.ModelName,
		Parent = opts.Parent,
		Style = {
			Uniform = opts.UniformColor,
			Vest = opts.VestColor,
			Helmet = opts.HelmetColor,
			Skin = opts.SkinColor or Color3.fromRGB(196, 151, 111),
			Accent = opts.AccentColor or Color3.fromRGB(70, 155, 220),
		},
	})
end

return SquadUnitBuilder
