class_name AttackResolver
extends RefCounted

const FULL_CHARGE_COST := 100.0
const FULL_CHARGE_DAMAGE := 34.0

static func try_attack(attacker: PlayerDuelState, defender: PlayerDuelState) -> Dictionary:
	if not attacker.can_spend(FULL_CHARGE_COST):
		attacker.set_result("NO CHARGE")
		return {
			"success": false,
			"heavy": false,
			"damage": 0.0,
			"message": "%s needs FULL CHARGE!" % attacker.display_name
		}

	attacker.spend_charge(FULL_CHARGE_COST)
	defender.take_damage(FULL_CHARGE_DAMAGE)
	attacker.set_result("AUTO BLAST")
	defender.set_result("BLASTED")
	return {
		"success": true,
		"heavy": true,
		"damage": FULL_CHARGE_DAMAGE,
		"message": "%s AUTO BLAST!" % attacker.display_name
	}
