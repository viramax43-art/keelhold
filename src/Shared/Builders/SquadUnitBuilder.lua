local CharacterRigBuilder = require(script.Parent.CharacterRigBuilder)

local SquadUnitBuilder = {}

function SquadUnitBuilder.CreateDefenderModel(opts)
	return CharacterRigBuilder.CreateR6Kit({
		SlotIndex = opts.SlotIndex,
		Position = opts.Position,
		FacingCFrame = opts.FacingCFrame,
		DisplayName = opts.DisplayName,
		WeaponType = opts.WeaponType,
		CurrentHP = opts.CurrentHP,
		MaxHP = opts.MaxHP,
		IsBot = opts.IsBot,
		ModelName = opts.ModelName,
		Parent = opts.Parent,
		Kit = {
			Uniform = opts.UniformColor,
			Vest = opts.VestColor,
			Helmet = opts.HelmetColor,
		},
	})
end

return SquadUnitBuilder
