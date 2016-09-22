Extended PaintBall Gamemode
===================
Pretty basic concept which turns bullets into physical objects at a certain speed.

<more documentation needed>

Gameplay
========
This can be triggered per player basis, or server-wide. All weapons will be turned into paintball guns, even shot guns. 
Players weapons should be regulated with another plugin.

<more documentation needed>

ConVars
========
Most of these will change in the future.

`sm_paintball_enable <0/1>` will disable/enable the painball gamemode.

`sm_paintball_halt <0/1>` will temporarily disable/enable the paintball gamemode, usefull for map makers.

`sm_paintball_damage <0.0-X.X>` will multiply the damage done by the configured weapon's damage.

`sm_paintball_firerate <0.0-X.X>` Fire rate multiplier. *WARNING* Do not set too low, server may lag or crash.

`sm_paintball_speed <0.0-X.X>` Velocity multiplier, the way this works may change later on.

`sm_paintball_hsdistance <0.0-X.X>` Cheap way of detecting if the bullet hit the player in the head, set to 0.0 to disable.

`sm_paintball_gravity_override <0/1>` Overrides the configed weapon's gravity.

`sm_paintball_gravity <0.0-X.X>` Gravity for the paint ball

`sm_paintball_nodrop <0/1>` Determines if the paintball should fly through the air (MOVETYPE_FLY)

<more documentation needed>

Config
========
There is a config for the weapons that can be setup for custom weapon damages and speeds. If no damage or firerate is setup then it will use the gamedata to find the damage/firerate.

Sample Weapon Config:
```
"PBWeapons"
{
	"weapon_base"
	{
		"enable"		"1" //Enable this weapon to shoot paintballs (Default 0)
		"FullAuto"		"1" //Constantly fire while holding down the mouse button.
		"Damage"		"38" //Damage done on impact
		"Bullets"		"1" //Bullets shot
		"CycleTime"		"0.1" //Fire rate of the weapon.
		"clip_size"		"30" //Clipsize of the weapon, currently uses gamedata to find this.
		"gravity"		"0.2" //The gravity of the paintballs this weapon shoots
		"speed"		"1600.0" //The base speed of the paintballs this weapon shoots
	}
}
```

<more documentation needed>
