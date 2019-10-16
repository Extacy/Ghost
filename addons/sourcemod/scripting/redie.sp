#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <entity>
#include <regex>
#include <clientprefs>

#pragma newdecls required

#define REDIE_PREFIX " \x01[\x03Redie\x01]\x04" // Replace with your server's custom prefix / colours.
EngineVersion g_Game;

// Client Preferences
Handle g_hViewPlayers; // Cookie to enable/disable viewing other players in Redie
Handle g_hRedieBanned; // Cookie for if player is banned from Redie.

// ConVars
ConVar g_cRedieEnabled; // Set if Redie is enabled or disabled on the server.
ConVar g_cRedieBhop; // Set whether to allow/disallow autobhop in Redie.
ConVar g_cRedieSpeed; // Set whether to allow/disallow unlimited speed in Redie.
ConVar g_cRedieNoclip; // Set whether to allow/disallow unlimited noclip in Redie.
ConVar g_cRedieModel; // Set whether to create a fake playermodel for players in Redie. (So players can see eachother)
ConVar g_cRedieCustomModel; // Set whether to use a custom model from server's FastDL or use the player's current model/skin
ConVar g_cRedieAdverts; // Set to enable/disable Redie adverts.
ConVar sv_autobunnyhopping; // sv_autobunnyhopping replicated ConVar for autobhop in Redie
ConVar sv_enablebunnyhopping; // Used for unlimited speed when bhopping

// Variables
bool g_bInRedie[MAXPLAYERS + 1]; // Clients currently in Redie
bool g_bBlockSounds[MAXPLAYERS + 1]; // Clients that cannot make sounds (this is used because g_bInRedie must be set to false when respawning player.)
bool g_bBhopEnabled[MAXPLAYERS + 1]; // Clients in Redie that have Bhop Enabled.
bool g_bSpeedEnabled[MAXPLAYERS + 1]; // Clients in Redie with unlimited speed enabled (sv_enablebunnyhopping)
bool g_bNoclipEnabled[MAXPLAYERS + 1]; // Cients in Redie with noclip enabled
bool g_bRedieBlocked; // Disable the use of redie during freezetime and when the round is about to end.


int g_iRedieProp[MAXPLAYERS + 1]; // Array of prop_dynamic for each player in redie
int g_iLastUsedCommand[MAXPLAYERS + 1]; // Array of clients and the time they last used a Redie command. (Used for cooldown.)
int g_iCoolDownTimer = 5; // How long, in seconds, should the cooldown between redie commands be
int g_iLastButtons[MAXPLAYERS + 1]; // Last used button (+use, +reload etc) for players in Redie. - Used for noclip

float g_fSaveLocation[MAXPLAYERS + 1][3]; // Save position for Redie

char g_sMapName[32]; // Clouds rotating block fix

// Natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Redie_InRedie", Native_InRedie);
	return APLRes_Success;
}

public int Native_InRedie(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_bInRedie[client];
}

public Plugin myinfo = 
{
	name = "Redie - Improved", 
	author = "Extacy", 
	description = "Improved Redie.", 
	version = "1.0", 
	url = "https://steamcommunity.com/profiles/76561198183032322"
};

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if (g_Game != Engine_CSGO && g_Game != Engine_CSS)
	{
		SetFailState("This plugin is for CS:GO/CSS only.");
	}
	
	g_hViewPlayers = RegClientCookie("redie_viewplayers", "", CookieAccess_Private);
	g_hRedieBanned = RegClientCookie("redie_banned", "", CookieAccess_Private);
	
	LoadTranslations("common.phrases.txt");
	
	HookEvent("round_start", Event_PreRoundStart, EventHookMode_Pre);
	HookEvent("round_end", Event_PreRoundEnd, EventHookMode_Pre);
	HookEvent("player_death", Event_PrePlayerDeath, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	AddNormalSoundHook(OnNormalSoundPlayed);
	
	CreateTimer(120.0, Timer_RedieAdvert, _, TIMER_REPEAT);
	
	HookUserMessage(GetUserMessageId("TextMsg"), RemoveCashRewardMessage, true);
	
	g_cRedieEnabled = CreateConVar("sm_redie_enabled", "1", "Set whether or not Redie is enabled on the server.");
	g_cRedieBhop = CreateConVar("sm_redie_bhop", "1", "Set whether to enable or disable autobhop in Redie.");
	g_cRedieSpeed = CreateConVar("sm_redie_speed", "1", "Set whether to allow players in Redie to use unlimited speed (sv_enablebunnyhopping)");
	g_cRedieNoclip = CreateConVar("sm_redie_noclip", "1", "Set whether to allow players in Redie to noclip");
	g_cRedieModel = CreateConVar("sm_redie_model", "0", "Set whether to spawn a fake playermodel so players in Redie can see eachother");
	g_cRedieCustomModel = CreateConVar("sm_redie_custom_model", "1", "Set whether to use a custom or default playermodel for ghosts in Redie.");
	g_cRedieAdverts = CreateConVar("sm_redie_adverts", "1", "Set whether to enable or disable Redie adverts (2 min interval).");
	
	sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
	sv_enablebunnyhopping = FindConVar("sv_enablebunnyhopping");
	SetConVarFlags(sv_autobunnyhopping, GetConVarFlags(sv_autobunnyhopping) & ~FCVAR_REPLICATED);
	SetConVarFlags(sv_enablebunnyhopping, GetConVarFlags(sv_enablebunnyhopping) & ~FCVAR_REPLICATED);
	
	RegConsoleCmd("sm_redie", CMD_Redie, "Respawn as a ghost.");
	RegConsoleCmd("sm_unredie", CMD_Unredie, "Return to spectator.");
	RegConsoleCmd("sm_rmenu", CMD_RedieMenu, "Display Redie menu.");
	RegAdminCmd("sm_inredie", CMD_InRedie, ADMFLAG_KICK, "Returns if player is in Redie, also used for Redie Admin Menu");
	
	for (int i = 0; i <= MaxClients; i++)
	if (IsValidClient(i))
		OnClientPutInServer(i);
}

public void OnClientCookiesCached(int client)
{
	char buffer[12];
	
	GetClientCookie(client, g_hRedieBanned, buffer, sizeof(buffer));
	if (StrEqual(buffer, ""))
	{
		SetClientCookie(client, g_hRedieBanned, "0");
	}
	
	GetClientCookie(client, g_hViewPlayers, buffer, sizeof(buffer));
	if (StrEqual(buffer, ""))
	{
		SetClientCookie(client, g_hViewPlayers, "1");
	}
}

public void OnMapStart()
{
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));
	
	PrecacheModel("models/props/cs_militia/bottle02.mdl");
	
	if (g_cRedieModel.BoolValue)
	{
		PrecacheModel("models/playpark/ghost.mdl");
		AddFileToDownloadsTable("models/playpark/ghost.mdl");
		AddFileToDownloadsTable("models/playpark/ghost.vvd");
		AddFileToDownloadsTable("models/playpark/ghost.dx90.vtx");
		AddFileToDownloadsTable("materials/playpark/ghost/ghost.vtf");
		AddFileToDownloadsTable("materials/playpark/ghost/ghost.vmt");
	}
}

public void OnClientPutInServer(int client)
{
	if (IsValidClient(client))
	{
		g_iLastUsedCommand[client] = 0;
		g_bInRedie[client] = false;
		g_bBlockSounds[client] = false;
		g_bBhopEnabled[client] = false;
		g_bSpeedEnabled[client] = false;
		g_bNoclipEnabled[client] = false;
		g_fSaveLocation[client] = view_as<float>( { -1.0, -1.0, -1.0 } );
		
		if (g_cRedieBhop.BoolValue)
			SendConVarValue(client, sv_autobunnyhopping, "0");
		if (g_cRedieSpeed.BoolValue)
			SendConVarValue(client, sv_enablebunnyhopping, "0");
		
		SDKHook(client, SDKHook_PreThink, Hook_PreThink);
		SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "trigger_teleport"))
	{
		SDKHookEx(entity, SDKHook_EndTouch, FakeTriggerTeleport);
		SDKHookEx(entity, SDKHook_StartTouch, FakeTriggerTeleport);
		SDKHookEx(entity, SDKHook_Touch, FakeTriggerTeleport);
	}
	
	// Hotfix to stop players in Redie from stopping the rotating block on clouds. Will implement a more permanent fix in the future.
	if (StrEqual(classname, "func_rotating") && StrEqual(g_sMapName, "jb_clouds_final5"))
	{
		SetEntProp(entity, Prop_Send, "m_usSolidFlags", 4);
	}
}

public Action RemoveCashRewardMessage(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	char buffer[64];
	PbReadString(msg, "params", buffer, sizeof(buffer), 0);
	
	if (StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_YouGotCash") ||
		StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_TeammateGotCash") ||
		StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_EnemyGotCash"))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

// Commands
public Action CMD_Redie(int client, int args)
{
	if (!g_cRedieEnabled.BoolValue)
	{
		ReplyToCommand(client, "%s Redie has been temporarily disabled on this server..", REDIE_PREFIX);
		return Plugin_Handled;
	}
	
	if (AreClientCookiesCached(client))
	{
		char sRedieBanned[12];
		GetClientCookie(client, g_hRedieBanned, sRedieBanned, sizeof(sRedieBanned));
		
		if (!StringToInt(sRedieBanned))
		{
			if (IsValidClient(client))
			{
				if (!g_bRedieBlocked)
				{
					if (!GameRules_GetProp("m_bWarmupPeriod"))
					{
						if (!IsPlayerAlive(client))
						{
							int time = GetTime();
							if (time - g_iLastUsedCommand[client] < g_iCoolDownTimer)
							{
								ReplyToCommand(client, "%s Too many commands issued! Please wait %i seconds before using that command again.", REDIE_PREFIX, g_iCoolDownTimer - (time - g_iLastUsedCommand[client]));
								return Plugin_Handled;
							}
							else
							{
								Redie(client);
								ShowRedieMenu(client);
								g_iLastUsedCommand[client] = time;
								return Plugin_Handled;
							}
						}
						else
						{
							ReplyToCommand(client, "%s You must be dead in order to use Redie.", REDIE_PREFIX);
							return Plugin_Handled;
						}
					}
					else
					{
						ReplyToCommand(client, "%s Redie is disabled during warmup.", REDIE_PREFIX);
						return Plugin_Handled;
					}
				}
				else
				{
					ReplyToCommand(client, "%s Please wait for the round to begin.", REDIE_PREFIX);
					return Plugin_Handled;
				}
			}
			else
			{
				ReplyToCommand(client, "%s You must be a valid client in order to use Redie.", REDIE_PREFIX);
				return Plugin_Handled;
			}
		}
		else
		{
			ReplyToCommand(client, "%s You are currently banned from using Redie!", REDIE_PREFIX);
			return Plugin_Handled;
		}
	}
	else
	{
		ReplyToCommand(client, "%s Client preferences haven't loaded yet! Try again.", REDIE_PREFIX);
		return Plugin_Handled;
	}
}

public Action CMD_Unredie(int client, int args)
{
	if (!g_cRedieEnabled.BoolValue)
	{
		ReplyToCommand(client, "%s Redie has been temporarily disabled on this server..", REDIE_PREFIX);
		return Plugin_Handled;
	}
	
	if (!g_bInRedie[client])
	{
		ReplyToCommand(client, "%s You must be in Redie to use this command.", REDIE_PREFIX);
		return Plugin_Handled;
	}
	else
	{
		int time = GetTime();
		if (time - g_iLastUsedCommand[client] < g_iCoolDownTimer)
		{
			ReplyToCommand(client, "%s Too many commands issued! Please wait %i seconds before using that command again.", REDIE_PREFIX, g_iCoolDownTimer - (time - g_iLastUsedCommand[client]));
			return Plugin_Handled;
		}
		else
		{
			if (g_bRedieBlocked)
			{
				ReplyToCommand(client, "%s Please wait for the round to begin.", REDIE_PREFIX);
				return Plugin_Handled;
			}
			else
			{
				Unredie(client);
				g_iLastUsedCommand[client] = time;
				return Plugin_Handled;
			}
		}
	}
}

public Action CMD_RedieMenu(int client, int args)
{
	if (g_bInRedie[client])
	{
		ShowRedieMenu(client);
		ReplyToCommand(client, "%s Opening Redie menu.", REDIE_PREFIX);
	}
	else
	{
		ReplyToCommand(client, "%s You must be in Redie to use this command!", REDIE_PREFIX);
	}
	return Plugin_Handled;
}

public Action CMD_InRedie(int client, int args)
{
	if (args != 1)
	{
		Menu menu = new Menu(InRedieMenuHandler);
		menu.SetTitle("Players in Redie");
		
		for (int i = 0; i <= MaxClients; i++)
		{
			if (g_bInRedie[i])
			{
				char index[16], name[32];
				IntToString(i, index, sizeof(index));
				GetClientName(i, name, sizeof(name));
				
				menu.AddItem(index, name);
			}
		}
		
		menu.Display(client, MENU_TIME_FOREVER);
		return Plugin_Handled;
	}
	
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	
	int target = FindTarget(0, arg);
	
	if (target == -1)
	{
		ReplyToCommand(client, "%s Player %s was not found.", REDIE_PREFIX, arg);
	}
	else
	{
		if (g_bInRedie[target])
		{
			ShowRedieAdminMenu(client, target);
			ReplyToCommand(client, "%s Player %N IS in Redie.", REDIE_PREFIX, target);
		}
		else
		{
			ReplyToCommand(client, "%s Player %N is NOT in Redie.", REDIE_PREFIX, target);
			
			char name[64];
			GetClientName(target, name, sizeof(name));
			
			Menu menu = new Menu(RedieAdminMenuHandler);
			
			if (AreClientCookiesCached(client))
			{
				char sRedieBanned[12];
				GetClientCookie(target, g_hRedieBanned, sRedieBanned, sizeof(sRedieBanned));
				
				if (StringToInt(sRedieBanned))
				{
					menu.AddItem("mapban", "Unban player from Redie");
					Format(name, sizeof(name), "Player: %s (%i) [BANNED]", name, GetClientUserId(target));
				}
				else
				{
					menu.AddItem("mapban", "Ban player from Redie");
					Format(name, sizeof(name), "Player: %s (%i)", name, GetClientUserId(target));
				}
			}
			
			menu.SetTitle(name);
			menu.Display(client, MENU_TIME_FOREVER);
		}
		
	}
	
	return Plugin_Handled;
}

// Events
public Action Event_PrePlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	if (g_bInRedie[client])
	{
		g_bBhopEnabled[client] = false;
		g_bSpeedEnabled[client] = false;
		g_bNoclipEnabled[client] = false;
		
		if (g_cRedieBhop.BoolValue)
			SendConVarValue(client, sv_autobunnyhopping, "0");
		if (g_cRedieSpeed.BoolValue)
			SendConVarValue(client, sv_enablebunnyhopping, "0");
		
		CreateTimer(1.0, Timer_ResetValue, userid);
		
		int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (ragdoll > 0 && IsValidEdict(ragdoll))
		{
			if (ragdoll != INVALID_ENT_REFERENCE)
			{
				AcceptEntityInput(ragdoll, "Kill");
			}
		}
		return Plugin_Handled;
	}
	
	PrintToChat(client, "%s Type /redie to respawn as a ghost!", REDIE_PREFIX);
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClient(client))
	{
		if (!g_bInRedie[client])
		{
			g_bBhopEnabled[client] = false;
			g_bSpeedEnabled[client] = false;
			g_bNoclipEnabled[client] = false;
			if (g_cRedieBhop.BoolValue)
				SendConVarValue(client, sv_autobunnyhopping, "0");
			if (g_cRedieSpeed.BoolValue)
				SendConVarValue(client, sv_enablebunnyhopping, "0");
		}
		
		SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit_Player);
	}
}

public Action OnNormalSoundPlayed(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
	if (IsValidClient(entity) && g_bBlockSounds[entity])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action Event_PreRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRedieBlocked = false;
	
	char entities[][] =  { "func_breakable", "func_button", "func_door", "func_door_rotating", "func_tanktrain", "func_tracktrain", "trigger_hurt", "trigger_multiple", "trigger_once" };
	for (int i = 0; i <= sizeof(entities) - 1; i++)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, entities[i])) != -1)
		{
			SDKHookEx(ent, SDKHook_EndTouch, BlockOnTouch);
			SDKHookEx(ent, SDKHook_StartTouch, BlockOnTouch);
			SDKHookEx(ent, SDKHook_Touch, BlockOnTouch);
		}
		
	}
	
	return Plugin_Continue;
}

public Action Event_PreRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRedieBlocked = true;
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (g_bInRedie[i] && IsValidClient(i))
		{
			g_bInRedie[i] = false;
			g_iRedieProp[i] = -1;
		}
	}
}

// Timers
public Action Timer_ResetValue(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	g_bInRedie[client] = false;
	g_bBlockSounds[client] = false;
	return Plugin_Stop;
}


public Action Timer_RedieAdvert(Handle timer)
{
	if (g_cRedieAdverts.BoolValue)
		PrintToChatAll("%s This server is running Redie! Type /redie", REDIE_PREFIX);
	
	return Plugin_Continue;
}


// SDKHooks
public Action Hook_SetTransmit_Prop(int entity, int client)
{
	// Hide yourself and also hide from players that are not in Redie.
	if (g_iRedieProp[client] == entity || !g_bInRedie[client])
	{
		return Plugin_Handled;
	}
	
	if (AreClientCookiesCached(client))
	{
		char sViewPlayers[12];
		GetClientCookie(client, g_hViewPlayers, sViewPlayers, sizeof(sViewPlayers));
		
		// Hide other Redie players if View Players is set to false.
		if (g_bInRedie[client] && !StringToInt(sViewPlayers) && entity > 1)
		{
			return Plugin_Handled;
		}
		
	}
	
	return Plugin_Continue;
}

public Action Hook_SetTransmit_Player(int entity, int client)
{
	// View other players in Redie.
	if (g_bInRedie[client] && g_bInRedie[entity] && entity != client)
		return Plugin_Continue;
	
	// Hide players in Redie from players that are still alive.
	if (!g_bInRedie[client] && g_bInRedie[entity])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

// Disable players in Redie from interacting with world by touch
public Action BlockOnTouch(int entity, int client)
{
	if (client && client <= MaxClients && g_bInRedie[client])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

// Teleport a player in Redie to the destination position of a trigger_teleport.
// This is done so players in Redie do not interact with trigger_teleports but still retain the functionality.
public Action FakeTriggerTeleport(int entity, int client)
{
	if (client && client <= MaxClients && g_bInRedie[client])
	{
		char landmark[64], buffer[64];
		float position[3];
		GetEntPropString(entity, Prop_Data, "m_target", landmark, sizeof(landmark));
		
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "info_teleport_destination")) != -1)
		{
			GetEntPropString(ent, Prop_Data, "m_iName", buffer, sizeof(buffer));
			if (StrEqual(landmark, buffer))
			{
				GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", position);
				TeleportEntity(client, position, NULL_VECTOR, NULL_VECTOR);
				break;
			}
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// Auto bhop / Unlimited Speed
public Action Hook_PreThink(int client)
{
	if (g_cRedieBhop.BoolValue)
	{
		if (!g_bBhopEnabled[client])
		{
			SetConVarBool(sv_autobunnyhopping, false);
			return Plugin_Continue;
		}
		else
		{
			SetConVarBool(sv_autobunnyhopping, true);
		}
	}
	
	if (g_cRedieSpeed.BoolValue)
	{
		if (!g_bSpeedEnabled[client])
		{
			SetConVarBool(sv_enablebunnyhopping, false);
			return Plugin_Continue;
		}
		else
		{
			SetConVarBool(sv_enablebunnyhopping, true);
		}
	}
	
	return Plugin_Continue;
}

// Disable weapons for players in Redie
public Action Hook_WeaponCanUse(int client, int weapon)
{
	if (g_bInRedie[client])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

// Redie Functions
public void Redie(int client)
{
	g_bBlockSounds[client] = true;
	g_bInRedie[client] = false; // This is done so the player can pick up their spawned weapons to remove them.
	CS_RespawnPlayer(client);
	g_bInRedie[client] = true;
	
	// Remove spawned in weapons
	int weaponIndex;
	for (int i = 0; i <= 5; i++)
	{
		while ((weaponIndex = GetPlayerWeaponSlot(client, i)) != -1)
		{
			RemovePlayerItem(client, weaponIndex);
			RemoveEdict(weaponIndex);
		}
	}
	
	if (g_cRedieBhop.BoolValue)
	{
		g_bBhopEnabled[client] = true;
		SendConVarValue(client, sv_autobunnyhopping, "1");
	}
	else
	{
		g_bBhopEnabled[client] = false;
		SendConVarValue(client, sv_autobunnyhopping, "0");
	}
	
	if (IsValidEdict(g_iRedieProp[client]) && g_iRedieProp[client] > 0)
	{
		AcceptEntityInput(g_iRedieProp[client], "Kill");
		g_iRedieProp[client] = -1;
	}
	
	// Create a fake playermodel so players in Redie can see each other.
	if (g_cRedieModel.BoolValue)
	{
		g_iRedieProp[client] = CreateEntityByName("prop_dynamic");
		if (IsValidEdict(g_iRedieProp[client]))
		{
			if (g_cRedieCustomModel.BoolValue)
			{
				DispatchKeyValue(g_iRedieProp[client], "model", "models/playpark/ghost.mdl");
			}
			else
			{
				char model[PLATFORM_MAX_PATH];
				GetClientModel(client, model, sizeof(model));
				DispatchKeyValue(g_iRedieProp[client], "model", model);
			}
			
			if (DispatchSpawn(g_iRedieProp[client]))
			{
				SetEntProp(g_iRedieProp[client], Prop_Send, "m_CollisionGroup", 1);
				SetEntProp(g_iRedieProp[client], Prop_Send, "m_nSolidType", 0);
				
				/*float pos[3], angles[3];
				GetClientAbsOrigin(client, pos);
				GetClientEyeAngles(client, angles);
				pos[2] += -15.0;
				
				TeleportEntity(g_iRedieProp[client], pos, angles, NULL_VECTOR);
				
				SetVariantString("!activator");
				AcceptEntityInput(g_iRedieProp[client], "SetParent", client, g_iRedieProp[client], 0);*/
				
				SDKHook(g_iRedieProp[client], SDKHook_SetTransmit, Hook_SetTransmit_Prop);
			}
		}
	}
	
	// Make player turn into a "ghost"
	SetEntityModel(client, "models/props/cs_militia/bottle02.mdl"); // Set the playermodel to a small item in order to not block buttons, knife swings or bullets.
	SetEntProp(client, Prop_Send, "m_lifeState", 1);
	SetEntData(client, FindSendPropInfo("CBaseEntity", "m_CollisionGroup"), 2, 4, true);
	SetEntProp(client, Prop_Data, "m_ArmorValue", 0);
	SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
	
	ReplyToCommand(client, "%s Respawned as a ghost.", REDIE_PREFIX);
}

public void OnGameFrame()
{
	// Using this temporarily because SetParent would not respect rotation
	if (g_cRedieModel.BoolValue)
	{
		for (int i = 0; i <= MaxClients; i++)
		{
			if (g_bInRedie[i] && IsValidEdict(g_iRedieProp[i]))
			{
				float angles[3], pos[3];
				GetClientAbsOrigin(i, pos);
				GetClientEyeAngles(i, angles);
				
				if (g_cRedieCustomModel.BoolValue)
					pos[2] += -15.0;
				
				angles[0] = 0.0;
				
				TeleportEntity(g_iRedieProp[i], pos, angles, NULL_VECTOR);
			}
		}
	}
}

public void Unredie(int client)
{
	if (g_bInRedie[client])
	{
		SetEntProp(client, Prop_Send, "m_lifeState", 0);
		SetEntProp(client, Prop_Data, "m_iFrags", GetClientFrags(client) + 1);
		SetEntProp(client, Prop_Data, "m_iDeaths", GetClientDeaths(client) - 1);
		ForcePlayerSuicide(client);
		
		if (IsValidEdict(g_iRedieProp[client]) && g_iRedieProp[client] > 0)
		{
			AcceptEntityInput(g_iRedieProp[client], "Kill");
			g_iRedieProp[client] = -1;
		}
		
		PrintToChat(client, "%s Returned to spectator.", REDIE_PREFIX);
	}
}


// Menu Handlers
public int RedieMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		if (g_bInRedie[param1])
		{
			switch (param2)
			{
				case 1:
				{
					if (!(g_fSaveLocation[param1][0] == -1.0 && 
							g_fSaveLocation[param1][1] == -1.0 && 
							g_fSaveLocation[param1][2] == -1.0))
					{
						float velocity[3] =  { 0.0, 0.0, 0.0 };
						TeleportEntity(param1, g_fSaveLocation[param1], NULL_VECTOR, velocity);
						PrintToChat(param1, "%s Teleported to your saved location!", REDIE_PREFIX);
					}
					else
					{
						PrintToChat(param1, "%s Save a location first!", REDIE_PREFIX);
					}
				}
				case 2:
				{
					GetClientAbsOrigin(param1, g_fSaveLocation[param1]);
					PrintToChat(param1, "%s Saved Location!", REDIE_PREFIX);
				}
				case 3:
				{
					if (g_cRedieNoclip.BoolValue)
					{
						if (g_bNoclipEnabled[param1])
						{
							SetEntityMoveType(param1, MOVETYPE_WALK);
							g_bNoclipEnabled[param1] = false;
							PrintToChat(param1, "%s Disabled Noclip!", REDIE_PREFIX);
						}
						else
						{
							SetEntityMoveType(param1, MOVETYPE_NOCLIP);
							g_bNoclipEnabled[param1] = true;
							PrintToChat(param1, "%s Enabled Noclip!", REDIE_PREFIX);
						}
					}
					else
					{
						SetEntityMoveType(param1, MOVETYPE_WALK);
					}
				}
				case 4:
				{
					if (g_cRedieBhop.BoolValue)
					{
						if (g_bBhopEnabled[param1])
						{
							SendConVarValue(param1, sv_autobunnyhopping, "0");
							g_bBhopEnabled[param1] = false;
							PrintToChat(param1, "%s Disabled Bhop!", REDIE_PREFIX);
						}
						else
						{
							SendConVarValue(param1, sv_autobunnyhopping, "1");
							g_bBhopEnabled[param1] = true;
							PrintToChat(param1, "%s Enabled Bhop!", REDIE_PREFIX);
						}
					}
				}
				case 5:
				{
					if (g_cRedieSpeed.BoolValue)
					{
						if (g_bSpeedEnabled[param1])
						{
							SendConVarValue(param1, sv_enablebunnyhopping, "0");
							g_bSpeedEnabled[param1] = false;
							PrintToChat(param1, "%s Disabled Unlimited Speed!", REDIE_PREFIX);
						}
						else
						{
							SendConVarValue(param1, sv_enablebunnyhopping, "1");
							g_bSpeedEnabled[param1] = true;
							PrintToChat(param1, "%s Enabled Unlimited Speed!", REDIE_PREFIX);
						}
					}
				}
				case 6:
				{
					if (AreClientCookiesCached(param1))
					{
						char sViewPlayers[12];
						GetClientCookie(param1, g_hViewPlayers, sViewPlayers, sizeof(sViewPlayers));
						
						if (StringToInt(sViewPlayers))
						{
							SetClientCookie(param1, g_hViewPlayers, "0");
							PrintToChat(param1, "%s Other players in Redie are now hidden!", REDIE_PREFIX);
						}
						else
						{
							SetClientCookie(param1, g_hViewPlayers, "1");
							PrintToChat(param1, "%s Other players in Redie are now unhidden!", REDIE_PREFIX);
						}
					}
					else
					{
						PrintToChat(param1, "%s You're settings haven't loaded yet. Try again.", REDIE_PREFIX);
					}
				}
				case 9:
				{
					return;
				}
			}
			ShowRedieMenu(param1);
		}
		else
		{
			delete menu;
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int InRedieMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		int player = StringToInt(info);
		if (IsValidClient(player))
			ShowRedieAdminMenu(param1, player);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int RedieAdminMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32], title[64];
		menu.GetItem(param2, info, sizeof(info));
		menu.GetTitle(title, sizeof(title));
		
		Regex regex = new Regex("\\((.*)\\)");
		
		if (regex.Match(title) > 0)
		{
			char buffer[128];
			regex.GetSubString(1, buffer, sizeof(buffer));
			
			int player = GetClientOfUserId(StringToInt(buffer));
			
			if (StrEqual(info, "teleport"))
			{
				float location[3];
				GetClientAbsOrigin(player, location);
				TeleportEntity(param1, location, NULL_VECTOR, NULL_VECTOR);
				PrintToChat(param1, "%s Teleported to %N", REDIE_PREFIX, player);
				ShowRedieAdminMenu(param1, player);
			}
			else if (StrEqual(info, "unredie"))
			{
				Unredie(player);
				PrintToChatAll("%s %N Forced Unredie on %N", REDIE_PREFIX, param1, player);
			}
			
			else if (StrEqual(info, "mapban"))
			{
				if (AreClientCookiesCached(param1))
				{
					char sRedieBanned[12];
					GetClientCookie(player, g_hRedieBanned, sRedieBanned, sizeof(sRedieBanned));
					
					if (StringToInt(sRedieBanned))
					{
						SetClientCookie(player, g_hRedieBanned, "0");
						PrintToChatAll("%s %N Unbanned player %N from Redie!", REDIE_PREFIX, param1, player);
					}
					else
					{
						Unredie(player);
						SetClientCookie(player, g_hRedieBanned, "1");
						PrintToChatAll("%s %N Banned player %N from Redie!", REDIE_PREFIX, param1, player);
					}
				}
				else
				{
					PrintToChat(param1, "%s Client preferences haven't loaded yet! Try again.", REDIE_PREFIX);
				}
			}
		}
		else
		{
			PrintToChat(param1, "%s Fatal Regex error. Please try again.", REDIE_PREFIX);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void ShowRedieMenu(int client)
{
	Panel panel = CreatePanel();
	panel.SetTitle("Redie Menu [sm_rmenu]");
	
	panel.DrawItem("Teleport");
	panel.DrawItem("Checkpoint");
	
	panel.DrawText(" ");
	if (g_cRedieNoclip.BoolValue)
	{
		if (g_bNoclipEnabled[client])
			panel.DrawItem("[✔] Noclip (R)");
		else
			panel.DrawItem("[X] Noclip (R)");
	}
	else
	{
		panel.DrawItem("[X] Noclip (Disabled)", ITEMDRAW_DISABLED);
	}
	
	if (g_cRedieBhop.BoolValue)
	{
		if (g_bBhopEnabled[client])
			panel.DrawItem("[✔] Auto Bhop");
		else
			panel.DrawItem("[X] Auto Bhop");
	}
	else
	{
		panel.DrawItem("[X] Auto Bhop (Disabled)", ITEMDRAW_DISABLED);
	}
	
	if (g_cRedieSpeed.BoolValue)
	{
		if (g_bSpeedEnabled[client])
			panel.DrawItem("[✔] Speed");
		else
			panel.DrawItem("[X] Speed");
	}
	else
	{
		panel.DrawItem("[X] Speed", ITEMDRAW_DISABLED);
	}
	
	if (AreClientCookiesCached(client))
	{
		char sViewPlayers[12];
		GetClientCookie(client, g_hViewPlayers, sViewPlayers, sizeof(sViewPlayers));
		
		if (g_cRedieModel.BoolValue)
		{
			if (StringToInt(sViewPlayers))
				panel.DrawItem("[✔] View Players");
			else
				panel.DrawItem("[X] View Players");
		}
		else
		{
			panel.DrawItem("", ITEMDRAW_NOTEXT);
		}
		
	}
	
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawText(" ");
	
	panel.DrawItem("Exit");
	panel.Send(client, RedieMenuHandler, MENU_TIME_FOREVER);
	delete panel;
}

public void ShowRedieAdminMenu(int client, int player)
{
	char name[64];
	GetClientName(player, name, sizeof(name));
	
	Menu menu = new Menu(RedieAdminMenuHandler);
	menu.AddItem("teleport", "Teleport to Player");
	menu.AddItem("unredie", "Unredie Player");
	
	if (AreClientCookiesCached(client))
	{
		char sRedieBanned[12];
		GetClientCookie(player, g_hRedieBanned, sRedieBanned, sizeof(sRedieBanned));
		
		if (StringToInt(sRedieBanned))
		{
			Format(name, sizeof(name), "Player: %s (%i) [BANNED]", name, GetClientUserId(player));
			menu.SetTitle(name);
			menu.AddItem("mapban", "Unban player from Redie");
		}
		else
		{
			Format(name, sizeof(name), "Player: %s (%i)", name, GetClientUserId(player));
			menu.SetTitle(name);
			menu.AddItem("mapban", "Ban player from Redie");
		}
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public Action OnPlayerRunCmd(int client, int & buttons, int & impulse, float vel[3], float angles[3], int & weapon, int & subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (g_bInRedie[client])
	{
		buttons &= ~IN_USE; // Block +use
		
		if (g_cRedieNoclip.BoolValue)
		{
			// Players in Redie can hold reload (R) to use noclip
			if (buttons & IN_RELOAD)
			{
				if (!(g_iLastButtons[client] & IN_RELOAD))
				{
					SetEntityMoveType(client, MOVETYPE_NOCLIP);
					g_bNoclipEnabled[client] = true;
				}
			}
			else if (g_iLastButtons[client] & IN_RELOAD)
			{
				SetEntityMoveType(client, MOVETYPE_WALK);
				g_bNoclipEnabled[client] = false;
			}
			g_iLastButtons[client] = buttons;
		}
	}
	
	return Plugin_Continue;
}


// Stocks
stock bool IsValidClient(int client)
{
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	if (IsFakeClient(client))return false;
	if (IsClientSourceTV(client))return false;
	return IsClientInGame(client);
} 