#pragma semicolon 1
#include <sdktools>
#include <sdkhooks>
//Maybe make this optional?
#include <WeaponAttachmentAPI>

//CSGO Specifics
#define DMG_HEADSHOT (1 << 29)
#define LASER_SPRITE "materials/sprites/laserbeam.vmt"
#define PB_SPLATTER "materials/decals/decal_paintsplatter002.vmt"

bool plyPaintBall[MAXPLAYERS+1] = {false, ...};
float plyNextShoot[MAXPLAYERS+1];

int precache_laser;
int pb_spray;

//Player Variables;
int plyWeapon[MAXPLAYERS+1];
//int plyBullets[MAXPLAYERS+1]; //Player could go into burstmode
bool plyEnabled[MAXPLAYERS+1];

//Weapon configs
// If not defined then it will use default.
#define MAXWEAPONS 50
bool wcAuto[MAXWEAPONS]; 
float wcDamage[MAXWEAPONS];
int wcBullets[MAXWEAPONS];
float wcCycle[MAXWEAPONS];
float wcGravity[MAXWEAPONS];
float wcSpeed[MAXWEAPONS];
int wcExp[MAXWEAPONS]; // 0 - Off, 1 - Multiply, 2 - Set damage
float wcExpDmg[MAXWEAPONS];
int wcExpRad[MAXWEAPONS];
int wcBounce[MAXWEAPONS];
float wcDecay[MAXWEAPONS];
StringMap wcWeaponLookup;

#define MAXSOUNDS 10 // How many sounds can be picked, if no sounds are defined use defaults
#define MIN_PITCH 0
#define MAX_PITCH 1
char wcShootSounds[MAXWEAPONS]; //Picks a random
char wcShootSoundList[MAXWEAPONS][MAXSOUNDS][128]; //Picks a random
int wcShootSoundPitch[MAXWEAPONS][MAXSOUNDS][2]; //Picks a random pitch between these two values
char wcImpactSounds[MAXWEAPONS]; //Picks a random
char wcImpactSoundList[MAXWEAPONS][MAXSOUNDS][128]; //Picks a random
int wcImpactSoundPitch[MAXWEAPONS][MAXSOUNDS][2]; //Picks a random pitch between these two values
char wcModel[MAXWEAPONS][128]; //Currently only one model can be defined.

//We need to have a system to prevent spawning too many bullets.
ArrayList bulletManager;

//Maybe we should have the colors either through config or convar?
static const int teamColors[4][4] = {{255,255,255,255}, {64,255,64,200}, {255,64,64,200}, {64,64,255,200}};

/* Convars */
ConVar cEnabled;
ConVar cDmgMultiplier;
ConVar cSpeedMultiplier;
ConVar cFireRateMultiplier;
ConVar cHeadShotDistance;
ConVar cDmgMultiplierHS;
ConVar cHalt;
ConVar cBulletGravity;
ConVar cBulletGravityOverride;
ConVar cBulletDrop;
ConVar cBulletExplode;
ConVar cBulletExpDmg;
ConVar cBulletExpRad;
ConVar cBulletBounce;
ConVar cBulletDecay;

bool playersCanShoot = true;

#define PLUGIN_VERSION "1.1.0"
public Plugin myinfo = {
	name = "Extended Paint Ball",
	author = "Mitch",
	description = "Custom Gamemode",
	version = PLUGIN_VERSION,
	url = "http://mtch.tech"
};

public OnPluginStart() {
	cEnabled = CreateConVar("sm_paintball_enable", "1", "Enable PaintBall");
	cDmgMultiplier = CreateConVar("sm_paintball_damage", "1.0", "Paintball Damage Multiplier");
	cFireRateMultiplier = CreateConVar("sm_paintball_firerate", "1.0", "Paintball Fire Rate Multiplier");
	cSpeedMultiplier = CreateConVar("sm_paintball_speed", "1.0", "Paintball Speed Multiplier"); //Too fast and it wont shoot straight.
	cHeadShotDistance = CreateConVar("sm_paintball_hsdistance", "150.0", "Paintball Headshot Distance");
	cDmgMultiplierHS = CreateConVar("sm_paintball_damagehs", "3.0", "Paintball Headshot Damage Multiplier");
	cHalt = CreateConVar("sm_paintball_halt", "0", "PB: temporarily stops paintballs");
	cBulletGravityOverride = CreateConVar("sm_paintball_gravity_override", "0", "PB: Allow the gravity convar to override the weapon's config");
	cBulletGravity = CreateConVar("sm_paintball_gravity", "0.2", "PB: Changes the bullet gravity");
	cBulletDrop = CreateConVar("sm_paintball_nodrop", "1", "PB: Should the bullet ever drop (MOVETYPE_FLY)");
	cBulletExplode = CreateConVar("sm_paintball_explode", "0", "PB: Should the bullet explode on impact (OVERRIDES CONFIG)");
	cBulletExpDmg = CreateConVar("sm_paintball_explode_damagemult", "1.0", "PB: Explosion Damage Multiplier (OVERRIDES CONFIG)");
	cBulletExpRad = CreateConVar("sm_paintball_explode_radius", "350", "PB: Explosion Damage Multiplier (OVERRIDES CONFIG)");
	cBulletBounce = CreateConVar("sm_paintball_bounce", "0", "PB: The amount of times the bullet should bounce before removal (OVERRIDES CONFIG)");
	cBulletDecay = CreateConVar("sm_paintball_decay", "-1.0", "PB: The amount of time the bullet will be removed. (OVERRIDES CONFIG)");

	AutoExecConfig(true);

	RegConsoleCmd("sm_paintball", Command_PaintBall, "Enable PaintBall mode");
	RegConsoleCmd("sm_pb", Command_PaintBall, "Enable PaintBall mode");

	loadOffsets();
	loadConfig();

	bulletManager = new ArrayList();

	//Events
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	CreateConVar("sm_paintball_version", PLUGIN_VERSION, "Paintball Version", FCVAR_SPONLY|FCVAR_DONTRECORD);
}

public void OnMapStart() {
	pb_spray = PrecacheModel(PB_SPLATTER);
	precache_laser = PrecacheModel(LASER_SPRITE);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	//Clear any stored bullets from last round.
	bulletManager.Clear();
	
	//Prevent firing paintballs in freeze time.
	playersCanShoot = false;
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	//Allow players to shoot.
	playersCanShoot = true;
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
}

public void loadConfig() {
	wcWeaponLookup = new StringMap();
	char sPaths[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPaths, sizeof(sPaths),"configs/paintball_weapons.cfg");
	KeyValues kv = new KeyValues("PBWeapons");
	FileToKeyValues(kv, sPaths);
	if (!kv.GotoFirstSubKey()) {
		SetFailState("Unable to load config");
		return;
	}
	char tempString[128];
	char sndBuffer[3][128];
	int tc;
	// 
	do {
		kv.GetSectionName(tempString, sizeof(tempString));

		if(kv.GetNum("enabled", 1) == 0) {
			//This weapon is disabled, next weapon.
			continue;
		}

		if(StrEqual(tempString, "default")) {
			//Default values, this SHOULD be the first key.
			tc = 0;
		} else {
			tc++;
		}

		wcWeaponLookup.SetValue(tempString, tc);
		wcAuto[tc]    =(kv.GetNum("FullAuto", 1)>0);
		wcDamage[tc]  = kv.GetFloat("Damage", 38.0);
		wcBullets[tc] = kv.GetNum("Bullets", 1);
		wcCycle[tc]   = kv.GetFloat("CycleTime", 0.1);
		wcGravity[tc] = kv.GetFloat("gravity", 0.2);
		wcSpeed[tc]   = kv.GetFloat("speed", 1600.0);
		wcExp[tc]     = kv.GetNum("explode", 0);
		wcExpDmg[tc]  = kv.GetFloat("explode_dmgmult", 2.0);
		wcExpRad[tc]  = kv.GetNum("explode_radius", 350);
		wcBounce[tc]  = kv.GetNum("bounce", 0);
		wcDecay[tc]   = kv.GetFloat("decay", 0.0);
		//wcSpread[tc]  = kv.GetFloat("spread", 0.0);

		//Get Weapon Shoot Sound
		for(int i=0; i < MAXSOUNDS;i++) {
			Format(tempString, sizeof(tempString), "shoot%i", i+1);
			kv.GetString(tempString, tempString, sizeof(tempString), "");
			if(!StrEqual(tempString, "", false)) {
				wcShootSounds[tc]++;
				ExplodeString(tempString, ";", sndBuffer, 3, 128, false);
				wcShootSoundList[tc][i] = sndBuffer[0];
				if(!StrEqual(sndBuffer[0], "")) {
					PrecacheSound(sndBuffer[0]);
				}
				wcShootSoundPitch[tc][i][MIN_PITCH] = NotZero(StringToInt(sndBuffer[1]), 100);
				wcShootSoundPitch[tc][i][MAX_PITCH] = NotZero(StringToInt(sndBuffer[2]), 100);
			}
		}

		//Get Weapon Impact Sound
		for(int i=0; i < MAXSOUNDS;i++) {
			Format(tempString, sizeof(tempString), "impact%i", i+1);
			kv.GetString(tempString, tempString, sizeof(tempString), "");
			if(!StrEqual(tempString, "", false)) {
				wcImpactSounds[tc]++;
				ExplodeString(tempString, ";", sndBuffer, 3, 128, false);
				wcImpactSoundList[tc][i] = sndBuffer[0];
				if(!StrEqual(sndBuffer[0], "")) {
					PrecacheSound(sndBuffer[0]);
				}
				wcImpactSoundPitch[tc][i][MIN_PITCH] = NotZero(StringToInt(sndBuffer[1]), 100);
				wcImpactSoundPitch[tc][i][MAX_PITCH] = NotZero(StringToInt(sndBuffer[2]), 100);
			}
		}

		//Get Paintball Splatter (later, need to add team splatters...)
		/*for(int i=0; i < MAXSOUNDS;i++) {
			Format(tempString, sizeof(tempString), "impact%i", i+1);
			kv.GetString(tempString, tempString, sizeof(tempString), "");
			if(!StrEqual(tempString, "", false)) {
				tempInt = ++wcImpactSounds[tc];
				if((StrContains(tempString, ";")) >= 0) {
					//Means there is a pitch.
					ExplodeString(tempString, ";", sndBuffer, 3, 128, false);
					wcShootSoundList[tc][tempInt] = sndBuffer[0];
					wcShootSoundPitch[tc][tempInt][0] = StringToInt(sndBuffer[1]);
					wcShootSoundPitch[tc][tempInt][1] = StringToInt(sndBuffer[2]);
					continue;
				}
				wcShootSoundList[tc][tempInt] = tempString;
			}
		}*/
		kv.GetString("model", wcModel[tc], 128, "");
		if(!StrEqual(wcModel[tc], "")) {
			//Model is not blank try to precache it.
			PrecacheModel(wcModel[tc]);
		}
	} while(kv.GotoNextKey());
	delete kv;
}

public int NotZero(int value, int def) {
	return (value == 0) ? def : value;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	static plyButtons[MAXPLAYERS+1];
	if((!plyPaintBall[client] && cEnabled.IntValue == 0) || !IsPlayerAlive(client) || !plyEnabled[client]) {
		return Plugin_Continue;
	}
	if(buttons & IN_RELOAD && !(plyButtons[client] & IN_RELOAD)) {
		checkReload(client, true);
	} else {
		if(buttons & IN_ATTACK) {
			float engineTime = GetGameTime();
			if(plyNextShoot[client] < engineTime) {
				//Check if player's weapon is auto or not.
				//Gun is full auto or the player wasn't holding attack before.
				if(playersCanShoot && !cHalt.BoolValue && (wcAuto[plyWeapon[client]] || !(plyButtons[client] & IN_ATTACK))) {
					fireWeapon(client, engineTime);
				}
			}
		} else if(plyButtons[client] & IN_ATTACK) {
			//Player releases attack1
			checkReload(client, false);
		}
	}
	plyButtons[client] = buttons;
	return Plugin_Continue;
}

public void fireWeapon(int client, float engineTime) {
	//Set the next time a player can fire their weapon:
	int id = plyWeapon[client];
	float fireRate = wcCycle[id] * cFireRateMultiplier.FloatValue;
	if(fireRate < 0.01) {
		fireRate = 0.01;
	}
	plyNextShoot[client] = engineTime + fireRate;

	//Check the weapon's clip
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
	if(clip <= 0) {
		//Don't fire if there's no ammo.
		return;
	}

	SetEntProp(weapon, Prop_Send, "m_iClip1", --clip);
	//Used to determine if the player can reload.
	SetEntProp(client, Prop_Send, "m_iShotsFired", GetEntProp(client, Prop_Send, "m_iShotsFired")+1);

	int paintBall = createPaintball(client, id);
	if(paintBall > 0) {
		SetEntPropEnt(paintBall, Prop_Send, "m_hThrower", weapon);
		//Teleport and Launch the paintball in the facing direction
		float shootPos[3];
		float endPos[3];
		float shootVel[3];
		WA_GetAttachmentPos(client, "muzzle_flash", shootPos);
		
		//Engage accuracy
		TraceEye(client, endPos);
		MakeVectorFromPoints(shootPos, endPos, shootVel);
		NormalizeVector(shootVel, shootVel);

		float speedMult = wcSpeed[id];
		if(cSpeedMultiplier.FloatValue != 1.0) {
			speedMult *= cSpeedMultiplier.FloatValue;
		}
		ScaleVector(shootVel, speedMult);

		float InitialAng[3];
		GetVectorAngles(shootVel, InitialAng);
		TeleportEntity(paintBall, shootPos, InitialAng, shootVel);
		int team = GetClientTeam(client);
		//Add Thin Trail
		SetEntityRenderColor(paintBall, teamColors[team][0], teamColors[team][1], teamColors[team][2], 255);
		TE_SetupBeamFollow(paintBall, precache_laser, -1, 0.2, 1.0, 0.0, 0, teamColors[team]);
		TE_SendToAll();
		//Shooting Sound Effects:
		int tempId = (wcShootSounds[id] > 0) ? id : 0;
		int soundId = GetRandomInt(0,wcShootSounds[tempId]-1);
		int pitch = GetRandomInt(wcShootSoundPitch[tempId][soundId][MIN_PITCH],wcShootSoundPitch[tempId][soundId][MAX_PITCH]);

		EmitSoundToAll(wcShootSoundList[tempId][soundId], client, _, _, _, 0.4, pitch, _, _, _, true, _);
	}
}

public void KillPaintBall(const char[] output, int paintBall, int activator, float delay) {
	removePaintBall(paintBall);
}

public void checkReload(int client, bool force) {
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(GetEntProp(weapon, Prop_Send, "m_iClip1") <= 0) {
		reloadOrSwitchWeapons(client, weapon);
	} else if(force) {
		reload(client, weapon);
	}
}

float SpinVel[3] = {0.0, 0.0, 0.0};
public int createPaintball(int client, int id) {
	int paintBall;
	if(bulletManager.Length > 1500) {
		//Remove the oldest paintball
		paintBall = bulletManager.Get(0);
		if(IsValidEntity(paintBall)) {
			AcceptEntityInput(paintBall, "Kill");
		}
		bulletManager.Erase(0);
	}

	paintBall = CreateEntityByName("decoy_projectile");
	if(paintBall > 0) {
		DispatchSpawn(paintBall);
		
		if(!StrEqual(wcModel[id], "")) {
			SetEntityModel(paintBall, wcModel[id]);
		} else {
			//Use default model
			SetEntityModel(paintBall, wcModel[0]);
		}
		
		SetEntPropVector(paintBall, Prop_Data, "m_vecAngVelocity", SpinVel);
		SetEntPropEnt(paintBall, Prop_Send, "m_hOwnerEntity", client);
		SetEntProp(paintBall, Prop_Send, "m_usSolidFlags", 12);
		
		//Gravity:
		if(cBulletDrop.BoolValue) {
			//Bullets should not drop while moving in the air.
			SetEntityMoveType(paintBall, MOVETYPE_FLY);
		}
		if(cBulletGravityOverride.BoolValue) {
			//Bullets will drop and gravity is not normal.
			SetEntityGravity(paintBall, cBulletGravity.FloatValue);
		} else {
			//Set the gravity to the configured amount.
			SetEntityGravity(paintBall, wcGravity[id]);
		}
		SetEntPropFloat(paintBall, Prop_Send, "m_flDamage", wcDamage[id]);
		SetEntProp(paintBall, Prop_Send, "m_nBody", id);
		
		int bounce = wcBounce[id];
		if(cBulletBounce.IntValue > 0) {
			bounce = cBulletBounce.IntValue;
		}
		SetEntProp(paintBall, Prop_Send, "m_nSkin", bounce);

		//Decay:
		char output[128];
		float decay = wcDecay[id];
		if(cBulletDecay.FloatValue > -1.0) {
			decay = cBulletDecay.FloatValue;
		}
		if(decay > 0.0) {
			Format(output, sizeof(output), "OnUser1 !self:FireUser2::%f:1", decay);
			SetVariantString(output);
			AcceptEntityInput(paintBall, "AddOutput");
			AcceptEntityInput(paintBall, "FireUser1");
			HookSingleEntityOutput(paintBall, "FireUser2", KillPaintBall, true);
		}
		
		SDKHook(paintBall, SDKHook_StartTouch, OnPaintBallTouch);
		bulletManager.Push(EntIndexToEntRef(paintBall));
	}
	return paintBall;
}

public Action OnPaintBallTouch(int paintBall, int other) {
	int owner = GetEntPropEnt(paintBall, Prop_Send, "m_hOwnerEntity");
	if(owner < 1 || owner > MaxClients || !IsClientInGame(owner)) {
		removePaintBall(paintBall);
		return Plugin_Continue;
	}
	int team = GetClientTeam(owner);
	float position[3];
	GetEntPropVector(paintBall, Prop_Send, "m_vecOrigin", position);
	float damage = GetEntPropFloat(paintBall, Prop_Send, "m_flDamage");
	int weapon = GetEntPropEnt(paintBall, Prop_Send, "m_hThrower");
	int id = GetEntProp(paintBall, Prop_Send, "m_nBody");
	if(other > 0 && other <= MaxClients && IsClientInGame(other) && IsPlayerAlive(other)) {
		//Hit Firing player or teammate:
		if(owner == other || team == GetClientTeam(other)) {
			return Plugin_Continue;
		}
		int dmgType = DMG_BULLET|DMG_NEVERGIB;
		if(cHeadShotDistance.FloatValue > 0.0) {
			//Shitty way of predicting if it was a headshot..
			float eyePos[3];
			GetClientEyePosition(other, eyePos);
			if(GetVectorDistance(position, eyePos, true) <= cHeadShotDistance.FloatValue) {
				dmgType |= DMG_HEADSHOT;
				damage *= cDmgMultiplierHS.FloatValue;
			}
		}
		//Damage Player
		damage *= cDmgMultiplier.FloatValue;
		//This ignores map damage filters..
		SDKHooks_TakeDamage(other, weapon, owner, damage, DMG_BULLET, weapon, NULL_VECTOR, NULL_VECTOR);
	} /* else { //Hit World
	} */

	//Setup an explode sprite:
	TE_SetupBloodSprite(position, NULL_VECTOR, teamColors[team], 25, pb_spray, pb_spray);
	TE_SendToAll();

	//Custom Impact sounds:
	int tempId = (wcImpactSounds[id] > 0) ? id : 0;
	int soundId = GetRandomInt(0,wcImpactSounds[tempId]-1);
	int pitch = GetRandomInt(wcImpactSoundPitch[tempId][soundId][MIN_PITCH],wcImpactSoundPitch[tempId][soundId][MAX_PITCH]);
	EmitSoundToAll(wcImpactSoundList[tempId][soundId], paintBall, _, _, _, 0.5, pitch, _, _, _, true, _);

	if(cBulletExplode.IntValue > 0 || wcExp[id] > 0) {
		//Create Explosion
		new explosion = CreateEntityByName("env_explosion");
		if (explosion != -1) {
			char className[64] = "decoy_projectile";
			if(IsValidEntity(weapon)) {
				GetWeaponClassname(weapon, className, sizeof(className));
			}
			//Code from homingmissles
			DispatchKeyValue(explosion, "classname", className);
			SetEntProp(explosion, Prop_Data, "m_spawnflags", 6146);
			if(cBulletExplode.IntValue > 0) {
				SetEntProp(explosion, Prop_Data, "m_iMagnitude", (cBulletExplode.IntValue==1) ? RoundFloat(damage * cBulletExpDmg.FloatValue) : RoundFloat(cBulletExpDmg.FloatValue)); 
				SetEntProp(explosion, Prop_Data, "m_iRadiusOverride", cBulletExpRad.IntValue); 
			} else if(wcExp[id] > 0) {
				SetEntProp(explosion, Prop_Data, "m_iMagnitude", (wcExp[id]==1) ? RoundFloat(damage * wcExpDmg[id]) : RoundFloat(wcExpDmg[id])); 
				SetEntProp(explosion, Prop_Data, "m_iRadiusOverride", wcExpRad[id]);
			}
			DispatchSpawn(explosion);
			ActivateEntity(explosion);
			TeleportEntity(explosion, position, NULL_VECTOR, NULL_VECTOR);
			SetEntPropEnt(explosion, Prop_Send, "m_hOwnerEntity", owner);
			SetEntProp(explosion, Prop_Send, "m_iTeamNum", team);
			AcceptEntityInput(explosion, "Explode");
			DispatchKeyValue(explosion, "classname", "env_explosion");
			AcceptEntityInput(explosion, "Kill");
		}
	}
	int bounce = GetEntProp(paintBall, Prop_Send, "m_nSkin", bounce);
	if(bounce > 0) {
		SetEntProp(paintBall, Prop_Send, "m_nSkin", --bounce);
	} else {
		removePaintBall(paintBall);
	}
	return Plugin_Continue;
}

public void removePaintBall(int paintBall) {
	//Clear paintball from bullet Manager
	int index = bulletManager.FindValue(EntRefToEntIndex(paintBall));
	if(index > -1) {
		bulletManager.Erase(index);
	}
	AcceptEntityInput(paintBall, "Kill");
}

public Action OnWeaponSwitch(int client, int weapon) {
	if(plyPaintBall[client] || cEnabled.IntValue > 0) {
		char className[64];
		GetWeaponClassname(weapon, className, sizeof(className));
		if(wcWeaponLookup.GetValue(className, plyWeapon[client])) {
			setWeaponNextShoot(weapon, 3600000.0);
			setNextShoot(client, 1.0);
			plyEnabled[client] = true;
		} else {
			plyEnabled[client] = false;
		}
	}
}

public Action Command_PaintBall(int client, int args) {
	togglePaintBallMode(client);
	return Plugin_Handled;
}
public void togglePaintBallMode(int client) {
	plyPaintBall[client] = !plyPaintBall[client];
	if(plyPaintBall[client]) {
		enablePaintBallMode(client);
	} else {
		disablePaintBallMode(client);
	}
}
public void enablePaintBallMode(int client) {
	//Enable Paintball mode for this player
	if(IsPlayerAlive(client)) {
		//Get clients active weapon from the config.
		int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		if(weapon > MaxClients && IsValidEntity(weapon)) {
			char className[64];
			GetWeaponClassname(weapon, className, sizeof(className));
			if(wcWeaponLookup.GetValue(className,plyWeapon[client])) {
				setWeaponNextShoot(weapon, 3600000.0);
				setNextShoot(client, 1.0);
				plyEnabled[client] = true;
			} else {
				plyEnabled[client] = false;
			}
		}
	}
}
public void disablePaintBallMode(int client) {
	//Disable Paintball mode for this player
	if(IsPlayerAlive(client)) {
		//If the player is alive we need to reset any netprops
		setPlayerNextShoot(client, 2.0);
	}
}
//Stock Functions:
public void setNextShoot(int client, float time) {
	plyNextShoot[client] = GetGameTime() + time;
}
public void setWeaponNextShoot(int weapon, float time) {
	float gameTime = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", time + gameTime);
}
public void setPlayerNextShoot(int client, float time) {
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	float gameTime = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", time + gameTime);
}

//TODO: remove this with a random spread mechanic.
public bool TraceEye(int client, float pos[3]) {
	float vAngles[3];
	float vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);
	Handle traceRay = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer, client);
	if(TR_DidHit(traceRay)) {
		TR_GetEndPosition(pos, traceRay);
		delete traceRay;
		return true;
	}
	delete traceRay;
	return false;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask, int client) {
	return (entity > MaxClients && entity != client);
}

Handle hReloadOrSwitchWeapons;
Handle hReload;
public void loadOffsets() {
	Handle hGameConf = LoadGameConfigFile("paintball.games");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "ReloadOrSwitchWeapons");
	if ((hReloadOrSwitchWeapons = EndPrepSDKCall()) == null) {
		LogError("[PaintBall] Unable to load ReloadOrSwitchWeapons offset");
	}
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Reload");
	if ((hReload = EndPrepSDKCall()) == null) {
		LogError("[PaintBall] Unable to load Reload offset");
	}
}

public void reloadOrSwitchWeapons(int client, int weapon) {
	sdkReload(client, weapon, hReloadOrSwitchWeapons);
}
public void reload(int client, int weapon) {
	sdkReload(client, weapon, hReload);
}
public void sdkReload(int client, int weapon, Handle sdkcall) {
	if(sdkcall != null) {
		float gameTime = GetGameTime();
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime-1.0);
		SDKCall(sdkcall, weapon);
		setNextShoot(client, GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") - gameTime);
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime+36000.0);
	}
}
/* Since cs:go likes to use items_game prefabs instead of weapon files on newly added weapons */
public void GetWeaponClassname(int weapon, char[] buffer, int size) {
	switch(GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")) {
		case 60: Format(buffer, size, "weapon_m4a1_silencer");
		case 61: Format(buffer, size, "weapon_usp_silencer");
		case 63: Format(buffer, size, "weapon_cz75a");
		case 64: Format(buffer, size, "weapon_revolver");
		default: GetEntityClassname(weapon, buffer, size);
	}
}
public bool isProgressiveReload(int weapon) {//m_reloadState
	switch(GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")) {
		case 25: return true; //XM
		case 29: return true; //Sawed off
		case 35: return true; //Nova
	}
	return false;
}