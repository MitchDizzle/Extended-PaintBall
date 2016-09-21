#pragma semicolon 1
#include <sdktools>
#include <sdkhooks>
//Maybe make this optional?
#include <WeaponAttachmentAPI>

//CSGO Specifics
#define DMG_HEADSHOT (1 << 29)

#define LASER_SPRITE "materials/sprites/laserbeam.vmt"
#define PB_SPLATTER "materials/decals/decal_paintsplatter002.vmt"
#define PB_MODEL "models/props/cs_office/plant01_gib1.mdl"

bool plyPaintBall[MAXPLAYERS+1] = {false, ...};
float plyNextShoot[MAXPLAYERS+1];
int precache_laser;
int pb_spray;

//Player Variables;
bool plyAuto[MAXPLAYERS+1];
float plyDamage[MAXPLAYERS+1];
float plyCycle[MAXPLAYERS+1];
int plyBullets[MAXPLAYERS+1];
int plyMaxClip[MAXPLAYERS+1];
bool plyEnabled[MAXPLAYERS+1];

//Weapon configs
// If not defined then it will use defaults.
#define MAXWEAPONS 50
bool wcAuto[MAXWEAPONS]; 
float wcDamage[MAXWEAPONS];
int wcBullets[MAXPLAYERS+1];
float wcCycle[MAXWEAPONS];
/*int wcCustomImpactSound; //Also stores how many different sounds there are for this weapon.
char wcImpactSound[MAXWEAPONS][MAXSOUNDS][128];
int wcCustomFireSound;
char wcFireSound[MAXWEAPONS][MAXSOUNDS][128];*/
StringMap wcWeaponLookup;

//We need to have a system to prevent spawning too many bullets.
// If we don't remove any of the bullets then the server will crash due to the engine limit.
ArrayList bulletManager;

//Default sounds:
#define MAXSOUNDS 10
/*int pbcImpactSoundCount;
char pbcImpactSound[MAXSOUNDS][128];
int pbcFireSoundCount;
char pbcFireSound[MAXSOUNDS][128];*/

static const int teamColors[4][4] = {
	{255,255,255,255},
	{64,255,64,200},
	{255,64,64,200},
	{64,64,255,200}
};

static const char sndImpact[4][] = {
	"physics/flesh/flesh_squishy_impact_hard1.wav",
	"physics/flesh/flesh_squishy_impact_hard2.wav",
	"physics/flesh/flesh_squishy_impact_hard3.wav",
	"physics/flesh/flesh_squishy_impact_hard4.wav"
};

static const char sndFire[1][] = {
	"doors/metal_door_full_close_02.wav",
};

/* Convars */
ConVar cEnabled;
ConVar cDmgMultiplier;
ConVar cSpeedMultiplier;
ConVar cFireRateMultiplier;
ConVar cHeadShotDistance;
ConVar cDmgMultiplierHS;
ConVar cHalt;

bool playersCanShoot = true;

#define PLUGIN_VERSION "1.0.0-BETA"
public Plugin myinfo = {
	name = "Paint Ball",
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
	PrecacheModel(PB_MODEL);
	pb_spray = PrecacheModel(PB_SPLATTER);
	PrecacheSound(sndImpact[0]);
	PrecacheSound(sndImpact[1]);
	PrecacheSound(sndImpact[2]);
	PrecacheSound(sndImpact[3]);
	PrecacheSound(sndFire[0]);
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
	Handle kv = CreateKeyValues("PBWeapons");
	FileToKeyValues(kv, sPaths);
	if (!KvGotoFirstSubKey(kv)) {
		SetFailState("Unable to load config");
		return;
	}
	char sectionName[64];
	int tc;
	do {
		tc++;
		KvGetSectionName(kv, sectionName, sizeof(sectionName));

		if(KvGetNum(kv, "enabled", 1) == 0) {
			//This weapon is disabled, next weapon.
			//The only reason this attiribute exists is to allow 
			// operators to keep the weapon in the config.
			tc--;
			continue;
		}
		PrintToChatAll(sectionName);
		wcWeaponLookup.SetValue(sectionName, tc);
		wcAuto[tc]   = (KvGetNum(kv, "FullAuto", 0)>0);
		wcDamage[tc] =  KvGetFloat(kv, "Damage", 38.0);
		wcBullets[tc] =  KvGetNum(kv, "Bullets", 1);
		wcCycle[tc]  = 	KvGetFloat(kv, "CycleTime", 0.1);
		//wcMax[tc]  = 	KvGetFloat(kv, "clip_size", 0.1);
		
	} while(KvGotoNextKey(kv));
	CloseHandle(kv);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	static plyButtons[MAXPLAYERS+1];
	if((!plyPaintBall[client] && cEnabled.IntValue == 0) || !IsPlayerAlive(client) || !plyEnabled[client]) {
		return Plugin_Continue;
	}
	//This is how cs weapons work (full auto):
	// 1. Holding attack shoots
	// 2. No ammo = no shoot
	// 3. Holding attack1 while no ammo does not reload the weapon
	// 4. Releasing attack1 with no ammo will automatically reload.
	if(buttons & IN_RELOAD && !(plyButtons[client] & IN_RELOAD)) {
		checkReload(client, true);
	} else {
		if(buttons & IN_ATTACK) {
			float engineTime = GetEngineTime();
			if(plyNextShoot[client] < engineTime) {
				//Check if player's weapon is auto or not.
				//Gun is full auto or the player wasn't holding attack before.
				if(playersCanShoot && !cHalt.BoolValue && (plyAuto[client] || !(plyButtons[client] & IN_ATTACK))) {
					fireWeapon(client, engineTime);
				}
			}
		} else if(plyButtons[client] & IN_ATTACK) {
			//Player releases attack1
			checkReload(client, false);
		}
	}
	//Check if buttons are in reload to reload the weapons
	plyButtons[client] = buttons;
	return Plugin_Continue;
}

public void fireWeapon(int client, float engineTime) {
	//Set the next time a player can fire their weapon:
	float fireRate = plyCycle[client] * cFireRateMultiplier.FloatValue;
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

	int paintBall = createPaintball(client);
	if(paintBall != -1) {
		
		SetEntPropEnt(paintBall, Prop_Send, "m_hThrower", weapon);
		//Teleport and Launch the paintball in the facing direction
		float shootPos[3];
		float endPos[3];
		float shootVel[3];
		WA_GetAttachmentPos(client, "muzzle_flash", shootPos);
		TraceEye(client, endPos);
		MakeVectorFromPoints(shootPos, endPos, shootVel);
		NormalizeVector(shootVel, shootVel);

		ScaleVector(shootVel, 3000.0);

		if(cSpeedMultiplier.FloatValue != 1.0) {
			ScaleVector(shootVel, cSpeedMultiplier.FloatValue);
		}

		float InitialAng[3];
		GetVectorAngles(shootVel, InitialAng);
		TeleportEntity(paintBall, shootPos, InitialAng, shootVel);
		int team = GetClientTeam(client);
		//Add Thin Trail
		SetEntityRenderColor(paintBall, teamColors[team][0], teamColors[team][1], teamColors[team][2], 255);
		TE_SetupBeamFollow(paintBall, precache_laser, -1, 0.2, 1.0, 0.0, 0, teamColors[team]);
		TE_SendToAll();
		//Sound Effects:
		EmitSoundToAll(sndFire[0], client, _, _, _, 0.4, GetRandomInt(85,100), _, _, _, true, _);
	}
}

public void checkReload(int client, bool force) {
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
	if(clip <= 0) {
		reloadOrSwitchWeapons(client, weapon);
	} else if(clip < plyMaxClip[client] && force) {
		reload(client, weapon);
	}
}

float SpinVel[3] = {0.0, 0.0, 0.0};
public int createPaintball(client) {
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
		SetEntityModel(paintBall, PB_MODEL);
		SetEntPropFloat(paintBall, Prop_Send, "m_flModelScale", 50.0);
		SetEntPropFloat(paintBall, Prop_Send, "m_flDamage", plyDamage[client]);
		SetEntPropVector(paintBall, Prop_Data, "m_vecAngVelocity", SpinVel);
		SetEntPropEnt(paintBall, Prop_Send, "m_hOwnerEntity", client);
		SetEntProp(paintBall, Prop_Data, "m_nNextThinkTick", -1);
		SetEntProp(paintBall, Prop_Send, "m_usSolidFlags", 12);
		SetEntPropString(paintBall, Prop_Data, "m_iszBounceSound", "");
		SetEntityMoveType(paintBall, MOVETYPE_FLY);
		SDKHook(paintBall, SDKHook_StartTouch, OnPaintBallTouch);
	}
	bulletManager.Push(EntIndexToEntRef(paintBall));
	return paintBall;
}

public Action OnPaintBallTouch(int paintBall, int other) {
	int owner = GetEntPropEnt(paintBall, Prop_Send, "m_hOwnerEntity");
	int team = GetClientTeam(owner);
	float position[3];
	GetEntPropVector(paintBall, Prop_Send, "m_vecOrigin", position);
	if(other > 0 && other <= MaxClients &&
		IsClientInGame(other) &&
		IsPlayerAlive(other)) {
		//Hit Firing player
		if(owner == other) {
			return Plugin_Continue;
		}
		//Let the paintball go through teammates:
		if(team == GetClientTeam(other)) {
			return Plugin_Continue;
		}
		int dmgType = DMG_BULLET|DMG_NEVERGIB;
		float damage = GetEntPropFloat(paintBall, Prop_Send, "m_flDamage");
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
		int weapon = GetEntPropEnt(paintBall, Prop_Send, "m_hThrower");
		damage *= cDmgMultiplier.FloatValue;
		//This ignores map damage filters..
		SDKHooks_TakeDamage(other, owner, owner, damage, DMG_BULLET, weapon, NULL_VECTOR, NULL_VECTOR);
	} else {
		//Hit World:
		/*int infodecal = CreateEntityByName("infodecal");
		SetEntProp(infodecal, Prop_Data, "m_nModelIndex", pb_spray);
		DispatchSpawn(infodecal);
		SetEntityRenderColor(infodecal, 255, 0, 0, 255);
		TeleportEntity(infodecal, position, NULL_VECTOR, NULL_VECTOR);*/
	}
	TE_SetupBloodSprite(position, NULL_VECTOR, teamColors[team], 25, pb_spray, pb_spray);
	TE_SendToAll();
	//Add custom sounds
	EmitSoundToAll(sndImpact[GetRandomInt(0,3)], paintBall, _, _, _, 0.5, _, _, _, _, true, _);
	
	//Clear paintball from bullet Manager
	int index = bulletManager.FindValue(EntRefToEntIndex(paintBall));
	if(index > -1) {
		 bulletManager.Erase(index);
	}
	AcceptEntityInput(paintBall, "Kill");
	
	return Plugin_Continue;
}

public Action OnWeaponSwitch(int client, int weapon) {
	if(plyPaintBall[client] || cEnabled.IntValue > 0) {
		char className[64];
		GetWeaponClassname(weapon, className, sizeof(className));
		int id;
		if(wcWeaponLookup.GetValue(className,id)) {
			setWeaponNextShoot(weapon, 3600000.0);
			setNextShoot(client, 1.0);
			plyAuto[client] = wcAuto[id];
			plyDamage[client] = wcDamage[id];
			plyCycle[client] = wcCycle[id];
			plyBullets[client] = wcBullets[id];
			plyMaxClip[client] = getMaxClip(weapon);
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
		//If the player is alive we need to set any netprops
		setPlayerNextShoot(client, 3600000.0);
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
	plyNextShoot[client] = GetEngineTime() + time;
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
Handle hGetMaxClip;
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
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "GetMaxClip1");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue); 
	if ((hGetMaxClip = EndPrepSDKCall()) == null) {
		LogError("[PaintBall] Unable to load GetMaxClip offset");
	}
}

public void reloadOrSwitchWeapons(int client, int weapon) {
	float gameTime = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime-1.0);
	SDKCall(hReloadOrSwitchWeapons, weapon);
	setNextShoot(client, GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") - gameTime);
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime+36000.0);
}

public void reload(int client, int weapon) {
	float gameTime = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime-1.0);
	SDKCall(hReload, weapon);
	setNextShoot(client, GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") - gameTime);
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime+36000.0);
}

public int getMaxClip(int weapon) {
	return SDKCall(hGetMaxClip, weapon);
}

public void GetWeaponClassname(int weapon, char[] buffer, int size) {
	/* Since cs:go likes to use items_game prefabs instead of weapon files on newly added weapons */
	switch(GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")) {
		case 60: {
			Format(buffer, size, "weapon_m4a1_silencer");
		}
		case 61: {
			Format(buffer, size, "weapon_usp_silencer");
		}
		case 63: {
			Format(buffer, size, "weapon_cz75a");
		}
		case 64: {
			Format(buffer, size, "weapon_revolver");
		}
		default: {
			GetEntityClassname(weapon, buffer, size);
		}
		
	}
}