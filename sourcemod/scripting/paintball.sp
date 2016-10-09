#pragma semicolon 1
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <WeaponAttachmentAPI>
bool useAttachmentAPI;

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

//Weapon configs (wc)
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
bool wcDrop[MAXWEAPONS]; 
StringMap wcWeaponLookup;

#define MAXSOUNDS 10 // How many sounds can be picked, if no sounds are defined use defaults
#define MIN_PITCH 0
#define MAX_PITCH 1
char wcShootSounds[MAXWEAPONS]; //Picks a random
int wcShootSoundIndex[MAXWEAPONS][MAXSOUNDS]; //Picks a random
int wcShootSoundPitch[MAXWEAPONS][MAXSOUNDS][2]; //Picks a random pitch between these two values
char wcImpactSounds[MAXWEAPONS]; //Picks a random
int wcImpactSoundIndex[MAXWEAPONS][MAXSOUNDS];
int wcImpactSoundPitch[MAXWEAPONS][MAXSOUNDS][2];
ArrayList wcSounds; //Holds all the sound files

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
ConVar cBulletDrop;
ConVar cBulletExplode;
ConVar cBulletExpDmg;
ConVar cBulletExpRad;
ConVar cBulletBounce;
ConVar cBulletDecay;

bool playersCanShoot = true;

#define PLUGIN_VERSION "1.2.0"
public Plugin myinfo = {
	name = "Extended Paint Ball",
	author = "Mitch",
	description = "Custom Gamemode",
	version = PLUGIN_VERSION,
	url = "http://mtch.tech"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	__pl_WeaponAttachmentAPI_SetNTVOptional();
}

public OnPluginStart() {
	cEnabled = CreateConVar("sm_paintball_enable", "1", "Enable PaintBall");
	cDmgMultiplier = CreateConVar("sm_paintball_damage", "1.0", "Paintball Damage Multiplier");
	cFireRateMultiplier = CreateConVar("sm_paintball_firerate", "1.0", "Paintball Fire Rate Multiplier");
	cSpeedMultiplier = CreateConVar("sm_paintball_speed", "1.0", "Paintball Speed Multiplier"); //Too fast and it wont shoot straight.
	cHeadShotDistance = CreateConVar("sm_paintball_hsdistance", "150.0", "Paintball Headshot Distance");
	cDmgMultiplierHS = CreateConVar("sm_paintball_damagehs", "3.0", "Paintball Headshot Damage Multiplier");
	cHalt = CreateConVar("sm_paintball_halt", "0", "PB: temporarily stops paintballs");
	cBulletGravity = CreateConVar("sm_paintball_gravity", "-1.0", "PB: Changes the bullet gravity");
	cBulletDrop = CreateConVar("sm_paintball_nodrop", "-1", "PB: Should the bullet ever drop (MOVETYPE_FLY)");
	cBulletExplode = CreateConVar("sm_paintball_explode", "-1", "PB: Should the bullet explode on impact (OVERRIDES CONFIG)");
	cBulletExpDmg = CreateConVar("sm_paintball_explode_damagemult", "-1.0", "PB: Explosion Damage Multiplier (OVERRIDES CONFIG)");
	cBulletExpRad = CreateConVar("sm_paintball_explode_radius", "-1", "PB: Explosion Damage Multiplier (OVERRIDES CONFIG)");
	cBulletBounce = CreateConVar("sm_paintball_bounce", "-1", "PB: The amount of times the bullet should bounce before removal (OVERRIDES CONFIG)");
	cBulletDecay = CreateConVar("sm_paintball_decay", "-1.0", "PB: The amount of time the bullet will be removed. (OVERRIDES CONFIG)");

	AutoExecConfig(true);

	loadOffsets();
	wcWeaponLookup = new StringMap();
	bulletManager = new ArrayList();
	wcSounds = new ArrayList(ByteCountToCells(128));

	//Events
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	CreateConVar("sm_paintball_version", PLUGIN_VERSION, "Paintball Version", FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	if(LibraryExists("WeaponAttachmentAPI")) {
		useAttachmentAPI = true;
	}
}

public OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "WeaponAttachmentAPI")) {
		useAttachmentAPI = true;
	}
}

public void OnMapStart() {
	pb_spray = PrecacheModel(PB_SPLATTER);
	precache_laser = PrecacheModel(LASER_SPRITE);
	loadConfig();
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
	wcWeaponLookup.Clear();
	wcSounds.Clear();
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
		wcDrop[tc]    =(kv.GetNum("nodrop", 1)>0);
		//wcSpread[tc]  = kv.GetFloat("spread", 0.0);

		//Get Weapon Shoot Sound
		wcShootSounds[tc] = 0;
		for(int i=0; i < MAXSOUNDS;i++) {
			Format(tempString, sizeof(tempString), "shoot%i", i+1);
			kv.GetString(tempString, tempString, sizeof(tempString), "");
			if(!StrEqual(tempString, "", false)) {
				wcShootSounds[tc]++;
				ExplodeString(tempString, ";", sndBuffer, 3, 128, false);
				if(!StrEqual(sndBuffer[0], "")) {
					wcShootSoundIndex[tc][i] = addSoundToList(wcSounds, sndBuffer[0]);
					wcShootSoundPitch[tc][i][MIN_PITCH] = NotZero(StringToInt(sndBuffer[1]), 100);
					wcShootSoundPitch[tc][i][MAX_PITCH] = NotZero(StringToInt(sndBuffer[2]), 100);
				}
			}
		}

		//Get Weapon Impact Sound
		wcImpactSounds[tc] = 0;
		for(int i=0; i < MAXSOUNDS;i++) {
			Format(tempString, sizeof(tempString), "impact%i", i+1);
			kv.GetString(tempString, tempString, sizeof(tempString), "");
			if(!StrEqual(tempString, "", false)) {
				wcImpactSounds[tc]++;
				ExplodeString(tempString, ";", sndBuffer, 3, 128, false);
				if(!StrEqual(sndBuffer[0], "")) {
					wcImpactSoundIndex[tc][i] = addSoundToList(wcSounds, sndBuffer[0]);
					wcImpactSoundPitch[tc][i][MIN_PITCH] = NotZero(StringToInt(sndBuffer[1]), 100);
					wcImpactSoundPitch[tc][i][MAX_PITCH] = NotZero(StringToInt(sndBuffer[2]), 100);
				}
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

public int addSoundToList(ArrayList list, char[] sound) {
	int index = list.FindString(sound);
	if(index == -1) {
		PrecacheSound(sound);
		return list.PushString(sound);
	}
	return index;
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
	
	if(GetEntProp(client, Prop_Send, "m_bIsDefusing") > 0 || GetEntProp(client, Prop_Send, "m_bIsGrabbingHostage") > 0) {
		return;
	}

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
		
		getShootPos(client, shootPos);
		
		//Engage accuracy
		TraceEye(client, endPos);
		MakeVectorFromPoints(shootPos, endPos, shootVel);
		NormalizeVector(shootVel, shootVel);

		float speedMult = wcSpeed[id];
		if(cSpeedMultiplier.FloatValue > -0.5) {
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
		char soundBuffer[128];
		if(wcSounds.GetString(wcShootSoundIndex[tempId][soundId], soundBuffer, sizeof(soundBuffer)) > 0) {
			EmitSoundToAll(soundBuffer, client, _, _, _, 0.4, pitch, _, _, _, true, _);
		}
	}
}

public void getShootPos(int client, float position[3]) {
	if(useAttachmentAPI) {
		WA_GetAttachmentPos(client, "muzzle_flash", position);
		return;
	}
	//Bommix's code
	float playerpos[3], playerangle[3], vecfwr[3];	
	GetClientEyePosition(client, playerpos);
	GetClientEyeAngles(client, playerangle);
	GetAngleVectors(playerangle, vecfwr, NULL_VECTOR, NULL_VECTOR);
	AddInFrontOf(playerpos, playerangle, 50.0, position);
}

stock void AddInFrontOf(float vecOrigin[3], float vecAngle[3], float units, float output[3]) {
	float vecAngVectors[3];
	vecAngVectors = vecAngle; //Don't change input
	GetAngleVectors(vecAngVectors, vecAngVectors, NULL_VECTOR, NULL_VECTOR);
	for (int i; i < 3; i++) {
		output[i] = vecOrigin[i] + (vecAngVectors[i] * units);
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

		SetEntPropFloat(paintBall, Prop_Send, "m_flDamage", wcDamage[id]);
		SetEntProp(paintBall, Prop_Send, "m_nBody", id);

		//Drop:
		bool drop = (cBulletDrop.IntValue > -1) ? (cBulletDrop.IntValue>0) : wcDrop[id];
		if(drop) {
			SetEntityMoveType(paintBall, MOVETYPE_FLY);
		}

		//Gravity:
		float gravity = wcGravity[id];
		if(cBulletGravity.FloatValue > -0.5) {
			//Bullets will drop and gravity is not normal.
			gravity = cBulletGravity.FloatValue;
		}
		SetEntityGravity(paintBall, gravity);

		//Bounce:
		int bounce = wcBounce[id];
		if(cBulletBounce.IntValue > -1) {
			bounce = cBulletBounce.IntValue;
		}
		SetEntProp(paintBall, Prop_Send, "m_nSkin", bounce);

		//Decay:
		char output[128];
		float decay = wcDecay[id];
		if(cBulletDecay.FloatValue > -0.5) {
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
				dmgType += DMG_HEADSHOT;
				damage *= cDmgMultiplierHS.FloatValue;
			}
		}
		//Damage Player
		if(cDmgMultiplier.FloatValue > -0.5) {
			damage *= cDmgMultiplier.FloatValue;
		}
		//This ignores map damage filters..
		SDKHooks_TakeDamage(other, (weapon != -1) ? weapon : owner, owner, damage, dmgType, weapon, NULL_VECTOR, NULL_VECTOR);
	} /* else { //Hit World
	} */

	//Setup an explode sprite:
	TE_SetupBloodSprite(position, NULL_VECTOR, teamColors[team], 25, pb_spray, pb_spray);
	TE_SendToAll();

	//Custom Impact sounds:
	int tempId = (wcImpactSounds[id] > 0) ? id : 0;
	int soundId = GetRandomInt(0,wcImpactSounds[tempId]-1);
	int pitch = GetRandomInt(wcImpactSoundPitch[tempId][soundId][MIN_PITCH],wcImpactSoundPitch[tempId][soundId][MAX_PITCH]);
	char soundBuffer[128];
	if(wcSounds.GetString(wcImpactSoundIndex[tempId][soundId], soundBuffer, sizeof(soundBuffer)) > 0) {
		EmitSoundToAll(soundBuffer, paintBall, _, _, _, 0.5, pitch, _, _, _, true, _);
	}

	//Explained: Convar override will work as -1,0,1. -1 Does not override and will use the weapon's property instead.
	if((cBulletExplode.IntValue == -1 && wcExp[id] > 0) || cBulletExplode.IntValue > 0) {
		//Create Explosion
		new explosion = CreateEntityByName("env_explosion");
		if (explosion != -1) {
			char className[64] = "decoy_projectile";
			if(IsValidEntity(weapon)) {
				GetWeaponClassname(weapon, className, sizeof(className));
			}
			//Code from homingmissles, butchered by me. :)
			DispatchKeyValue(explosion, "classname", className);
			SetEntProp(explosion, Prop_Data, "m_spawnflags", 6146);

			//Magnitude is a tad more complicated since there is two options for the override, set and multiply.
			int magnitude = (wcExp[id] > 1) ? RoundFloat(wcExpDmg[id]) : RoundFloat(damage * wcExpDmg[id]);
			if(cBulletExpDmg.FloatValue > -1) {
				magnitude = (cBulletExplode.IntValue > 1) ? RoundFloat(cBulletExpDmg.FloatValue) : RoundFloat(damage * cBulletExpDmg.FloatValue);
			}
			SetEntProp(explosion, Prop_Data, "m_iMagnitude", magnitude); 

			//Radius
			SetEntProp(explosion, Prop_Data, "m_iRadiusOverride", (cBulletExpRad.IntValue > -1) ? cBulletExpRad.IntValue : wcExpRad[id]); 

			DispatchSpawn(explosion);
			ActivateEntity(explosion);
			SetEntPropEnt(explosion, Prop_Send, "m_hOwnerEntity", owner);
			SetEntProp(explosion, Prop_Send, "m_iTeamNum", team);
			TeleportEntity(explosion, position, NULL_VECTOR, NULL_VECTOR);
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