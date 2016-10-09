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

`sm_paintball_explode <0/1>` Determines if the paintball should explode

`sm_paintball_explode_radius <0/X>` The damage multiplier for the explosion

`sm_paintball_explode_damagemult <0.0/X.X>` The damage multiplier for the explosion

`sm_paintball_bounce <0/X>` The amount of times that the paintball will bounce

`sm_paintball_decay <-1.0/X.X>` The amount of time before the paintball is removed, -1.0 to disable.

<more documentation needed>

Config
========
There is a config for the weapons that can be setup for custom weapon damages and speeds. If no damage or firerate is setup then it will use the gamedata to find the damage/firerate.

Sample Weapon Config:
```
"PBWeapons"
{
	"WEAPON_NAME"
	{
		"enable"			"1" //Enable this weapon to shoot paintballs (Default 1)
		"FullAuto"			"1" //Constantly fire while holding down the mouse button.
		"Damage"			"38" //Damage done on impact
		"Bullets"			"1" //Bullets shot
		"CycleTime"			"0.1" //Fire rate of the weapon.
		"gravity"			"0.2" //The gravity of the paintballs this weapon shoots
		"speed"				"1600.0" //The base speed of the paintballs this weapon shoots
		"explode"			"0" //1 Explodes on impact
		"explode_dmgmult"	"2.0" //Explosion damage multiplier
		"explode_radius"	"350" //Explosion Radius
		"bounce"			"0" //Times the paintball can bounce
		"decay"				"0.0" //Amount of time until the paintball is removed
		"model"				"MODEL_FILE_PATH"
		//Sounds can be listed from 1 to 10 (MAX_SOUNDS), X respresenting a number.
		"shootX"			"SOUND_FILE_PATH;MIN_PITCH;MAX_PITCH" //The custom shoot sound
		"impactX"			"SOUND_FILE_PATH;MIN_PITCH;MAX_PITCH"
	}
}
```

<more documentation needed>
