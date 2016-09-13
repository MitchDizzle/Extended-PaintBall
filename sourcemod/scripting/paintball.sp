#pragma semicolon 1
#include <sdktools>
#include <sdkhooks>
#include <WeaponAttachmentAPI>
#include <DHooks>

#define LASER_SPRITE "materials/sprites/laserbeam.vmt"
#define PB_SPLATTER "materials/decals/decal_paintsplatter002.vmt"
#define PB_MODEL "models/props/cs_office/plant01_gib1.mdl"

//"models/props/cs_italy/orange.mdl"
bool plyPaintBall[MAXPLAYERS+1] = {false, ...};
float plyNextShoot[MAXPLAYERS+1];
int precache_laser;
int pb_spray;

//Player Variables;
bool plyAuto[MAXPLAYERS+1];
float plyDamage[MAXPLAYERS+1];
float plyCycle[MAXPLAYERS+1];
bool plyEnabled[MAXPLAYERS+1];

#define MAXWEAPONS 50
//bool wcEnabled[MAXWEAPONS];
bool wcAuto[MAXWEAPONS];
float wcDamage[MAXWEAPONS];
float wcCycle[MAXWEAPONS];
int wcCount = 0;
StringMap wcWeaponLookup;

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

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "Paint Ball",
	author = "Mitch",
	description = "Custom Gamemode",
	version = PLUGIN_VERSION,
	url = "http://mtch.tech"
};

public OnPluginStart() {
	
	cEnabled = CreateConVar("sm_paintball_enable", "1", "Enable PaintBall");
	
	RegConsoleCmd("sm_paintball", Command_PaintBall, "Enable PaintBall mode");
	
	loadConfig();
	
	loadOffsets();
	
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
	
	CreateConVar("sm_paintball_version", PLUGIN_VERSION, "Paintball Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
}

public MRESReturn WeaponFinishReload(int pThis, Handle hReturn)
{
    //Make bots slow
	PrintToChatAll("FinishReload");
	return MRES_Ignored;
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

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
}

public void loadConfig() {
	wcWeaponLookup = new StringMap();
	wcCount = 0;
	char sPaths[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPaths, sizeof(sPaths),"configs/paintball_weapons.cfg");
	Handle kv = CreateKeyValues("PBWeapons");
	FileToKeyValues(kv, sPaths);
	if (!KvGotoFirstSubKey(kv)) {
		SetFailState("Unable to load config");
		return;
	}
	char tempText[32];
	char tempText2[32];
	int tempInt = 0;
	int tc;
	do {
		wcCount++;
		tc = wcCount;
		KvGetSectionName(kv, tempText, 12);
		//Easier lookup later on.
		tempInt = KvGetNum(kv, "goto", 0);
		if(tempInt > 0) {
			//Goto
			PrintToChatAll("%s Goto %i", tempText, tempInt);
			IntToString(tempInt, tempText2, sizeof(tempText2));
			if(wcWeaponLookup.GetValue(tempText2, tc)) {
				wcWeaponLookup.SetValue(tempText, tc);
			}
			wcCount--;
			continue;
		}
		
		tempInt = KvGetNum(kv, "enabled", 1);
		if(tempInt == 0) {
			wcCount--;
			continue;
		}
		wcWeaponLookup.SetValue(tempText, tc);
		wcAuto[tc]   = (KvGetNum(kv, "auto", 0)>0);
		wcDamage[tc] =  KvGetFloat(kv, "damage", 100.0);
		wcCycle[tc]  = 	KvGetFloat(kv, "cycle", 0.5);
		
	} while(KvGotoNextKey(kv));
	CloseHandle(kv);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	static plyButtons[MAXPLAYERS+1];
	if(!plyPaintBall[client] || !IsPlayerAlive(client) || !plyEnabled[client]) {
		return Plugin_Continue;
	}
	//Check if player's weapon is auto or not.
	if(buttons & IN_ATTACK) {
		//Player is holding attack.
		if(plyNextShoot[client] < GetEngineTime()) {
			if(plyAuto[client] || !(plyButtons[client] & IN_ATTACK)) {
				fireWeapon(client);
			}
		}
	}
	plyButtons[client] = buttons;
	return Plugin_Continue;
}

public void fireWeapon(int client) {
	float engineTime = GetEngineTime();
	plyNextShoot[client] = engineTime + plyCycle[client];
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	//PrintToChatAll("m_bReloadVisuallyComplete: %i", GetEntProp(weapon, Prop_Send, "m_bReloadVisuallyComplete"));
	int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
	if(clip <= 0) {
		reloadOrSwitchWeapons(client, weapon);
		return;
	}
	SetEntProp(weapon, Prop_Send, "m_iClip1", clip-1);
	SetEntProp(client, Prop_Send, "m_iShotsFired", GetEntProp(client, Prop_Send, "m_iShotsFired")+1);
	if(clip < 1) {
		reloadOrSwitchWeapons(client, weapon);
	}
	
	int paintBall = createPaintball(client);
	if(paintBall != -1) {
		//Teleport and Launch the paintball in the facing direction
		float shootPos[3];
		float endPos[3];
		float shootVel[3];
		WA_GetAttachmentPos(client, "muzzle_flash", shootPos);
		TraceEye(client, endPos);
		MakeVectorFromPoints(shootPos, endPos, shootVel);
		NormalizeVector(shootVel, shootVel);
		ScaleVector(shootVel, 3000.0);
		float InitialAng[3];
		GetVectorAngles(shootVel, InitialAng);
		TeleportEntity(paintBall, shootPos, InitialAng, shootVel);
		int team = GetClientTeam(client);
		//Add Trail
		SetEntityRenderColor(paintBall, teamColors[team][0], teamColors[team][1], teamColors[team][2], 255);
		TE_SetupBeamFollow(paintBall, precache_laser, -1, 0.2, 1.0, 0.0, 0, teamColors[team]);
		TE_SendToAll();
		//Sound Effects:
		EmitSoundToAll(sndFire[0], client, _, _, _, 0.4, GetRandomInt(85,100), _, _, _, true, _);
	}
}

new Float:SpinVel[3] = {0.0, 0.0, 0.0};
public int createPaintball(client) {
	int paintBall = CreateEntityByName("hegrenade_projectile");
	if(paintBall > 0) {
		DispatchSpawn(paintBall);
		SetEntityModel(paintBall, PB_MODEL);
		SetEntPropFloat(paintBall, Prop_Send, "m_flModelScale", 50.0);
		SetEntProp(paintBall, Prop_Send, "m_flDamage", plyDamage[client]);
		SetEntPropVector(paintBall, Prop_Data, "m_vecAngVelocity", SpinVel);
		SetEntPropEnt(paintBall, Prop_Send, "m_hOwnerEntity", client);
		SetEntProp(paintBall, Prop_Data, "m_nNextThinkTick", -1);
		SetEntProp(paintBall, Prop_Send, "m_usSolidFlags", 12);
		SetEntityMoveType(paintBall, MOVETYPE_FLY);
		SDKHook(paintBall, SDKHook_StartTouch, OnPaintBallTouch);
	}
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
		//Hit player
		if(owner == other) {
			return Plugin_Continue;
		}
		//Let the paintball go through teammates:
		if(team == GetClientTeam(other)) {
			return Plugin_Continue;
		}
		//Damage Player
		//Hurt player: m_ScaleType
		int weapon = GetEntPropEnt(paintBall, Prop_Send, "m_hThrower");
		float damage = GetEntPropFloat(paintBall, Prop_Send, "m_flDamage");
		SDKHooks_TakeDamage(other, weapon, owner, damage, DMG_BULLET, weapon, NULL_VECTOR, NULL_VECTOR);
	} else {
		//Hit World:
		int infodecal = CreateEntityByName("infodecal");
		SetEntProp(infodecal, Prop_Data, "m_nModelIndex", pb_spray);
		DispatchSpawn(infodecal);
		SetEntityRenderColor(infodecal, 255, 0, 0, 255);
		TeleportEntity(infodecal, position, NULL_VECTOR, NULL_VECTOR);
	}
	TE_SetupBloodSprite(position, NULL_VECTOR, teamColors[team], 25, pb_spray, pb_spray);
	TE_SendToAll();
	EmitSoundToAll(sndImpact[GetRandomInt(0,3)], paintBall, _, _, _, 0.5, _, _, _, _, true, _);
	AcceptEntityInput(paintBall, "Kill");
	return Plugin_Continue;
}

public Action OnWeaponSwitch(int client, int weapon) {
	if(plyPaintBall[client]) {
		setWeaponNextShoot(weapon, 3600000.0);
		setNextShoot(client, 1.0);
		int index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		char tempString[32];
		IntToString(index, tempString, sizeof(tempString));
		if(wcWeaponLookup.GetValue(tempString,index)) {
			plyAuto[client] = wcAuto[index];
			plyDamage[client] = getDamage(weapon);//wcDamage[index];
			plyCycle[client] = getFireRateWeapon(weapon);//wcCycle[index];
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
	//SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", time + gameTime);
}

public void setPlayerNextShoot(int client, float time) {
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	float gameTime = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", time + gameTime);
	//SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", time + gameTime);
	//SetEntPropFloat(client, Prop_Send, "m_flNextAttack", time + gameTime);
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
	return (entity >= 0 && entity != client);
}

Handle hReloadOrSwitchWeapons = INVALID_HANDLE;
Handle hGetFireRate = INVALID_HANDLE;
Handle hGetDamage = INVALID_HANDLE;
public void loadOffsets() {
	Handle hGameConf = LoadGameConfigFile("paintball.games");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "ReloadOrSwitchWeapons");
	if ((hReloadOrSwitchWeapons = EndPrepSDKCall()) == INVALID_HANDLE) {
		SetFailState("[PaintBall] Unable to load ReloadOrSwitchWeapons offset");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "GetFireRate");
	if ((hGetFireRate = EndPrepSDKCall()) == INVALID_HANDLE) {
		SetFailState("[PaintBall] Unable to load GetFireRate offset");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "GetDamage");
	if ((hGetDamage = EndPrepSDKCall()) == INVALID_HANDLE) {
		SetFailState("[PaintBall] Unable to load GetFireRate offset");
	}

}

public void reloadOrSwitchWeapons(int client, int weapon) {
	float gameTime = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime-1.0);
	SDKCall(hReloadOrSwitchWeapons, weapon);
	setNextShoot(client, GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") - gameTime);
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime+36000.0);
}

public float getFireRateWeapon(int weapon) {
	return SDKCall(hGetFireRate, weapon);
}

public float getDamage(int weapon) {
	return SDKCall(hGetDamage, weapon);
}



