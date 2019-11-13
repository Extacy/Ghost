#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <entity>
#include <regex>
#include <clientprefs>

#pragma newdecls required

#define CHAT_PREFIX " \x02[\x01Ghost\x02]\x01" 
#define CHAT_COLOR "\x01"
#define CHAT_ACCENT "\x0F"

EngineVersion g_Game;

// Client Preferences
Handle g_hViewPlayersCookie; // Cookie to toggle viewing other ghosts
Handle g_hBannedCookie; // Cookie for if player is banned from using Ghost.

// ConVars
ConVar g_cPluginEnabled;
ConVar g_cGhostBhop;
ConVar g_cGhostSpeed;
ConVar g_cGhostNoclip;
ConVar g_cChatAdverts;
ConVar g_cChatAdvertsInterval;
ConVar sv_autobunnyhopping;
ConVar sv_enablebunnyhopping;

// Plugin Variables
bool g_bIsGhost[MAXPLAYERS + 1]; // Current players that are a Ghost
bool g_bBlockSounds[MAXPLAYERS + 1]; // Clients that cannot make sounds (this is used because g_bIsGhost must be set to false when respawning player.)
bool g_bBhopEnabled[MAXPLAYERS + 1]; // Ghosts that have Bhop Enabled.
bool g_bSpeedEnabled[MAXPLAYERS + 1]; // Ghosts with unlimited speed enabled (sv_enablebunnyhopping)
bool g_bNoclipEnabled[MAXPLAYERS + 1]; // Ghosts with noclip enabled
bool g_bPluginBlocked; // Disable the use of Ghost during freezetime and when the round is about to end.

int g_iLastUsedCommand[MAXPLAYERS + 1]; // Array of clients and the time they last used a command. (Used for cooldown.)
int g_iCoolDownTimer = 5; // How long, in seconds, should the cooldown between commands be
int g_iLastButtons[MAXPLAYERS + 1]; // Last used button (+use, +reload etc) for ghosts. - Used for noclip

float g_fSaveLocation[MAXPLAYERS + 1][3]; // Save position location for ghosts


public Plugin myinfo = 
{
	name = "Ghost", 
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
	
	g_hViewPlayersCookie = RegClientCookie("ghost_viewplayers", "", CookieAccess_Private);
	g_hBannedCookie = RegClientCookie("ghost_banned", "", CookieAccess_Private);
	
	g_cPluginEnabled = CreateConVar("sm_ghost_enabled", "1", "Set whether Ghost is enabled on the server.");
	g_cGhostBhop = CreateConVar("sm_ghost_bhop", "1", "Set whether ghosts can autobhop.");
	g_cGhostSpeed = CreateConVar("sm_ghost_speed", "1", "Set whether ghosts can use unlimited speed (sv_enablebunnyhopping)");
	g_cGhostNoclip = CreateConVar("sm_ghost_noclip", "1", "Set whether ghosts can noclip.");
	g_cChatAdverts = CreateConVar("sm_ghost_adverts", "1", "Set whether chat adverts are enabled.");
	g_cChatAdvertsInterval = CreateConVar("sm_ghost_adverts_interval", "120.0", "Interval (in seconds) of chat adverts.");
	
	sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
	sv_enablebunnyhopping = FindConVar("sv_enablebunnyhopping");
	SetConVarFlags(sv_autobunnyhopping, GetConVarFlags(sv_autobunnyhopping) & ~FCVAR_REPLICATED);
	SetConVarFlags(sv_enablebunnyhopping, GetConVarFlags(sv_enablebunnyhopping) & ~FCVAR_REPLICATED);
	
	LoadTranslations("common.phrases.txt");
	
	HookEvent("round_start", Event_PreRoundStart, EventHookMode_Pre);
	HookEvent("round_end", Event_PreRoundEnd, EventHookMode_Pre);
	HookEvent("player_death", Event_PrePlayerDeath, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	AddNormalSoundHook(OnNormalSoundPlayed);
	
	CreateTimer(g_cChatAdvertsInterval.FloatValue, Timer_ChatAdvert, _, TIMER_REPEAT);
	
	HookUserMessage(GetUserMessageId("TextMsg"), RemoveCashRewardMessage, true);
	
	RegConsoleCmd("sm_ghost", CMD_Ghost, "Respawn as a ghost.");
	RegConsoleCmd("sm_redie", CMD_Ghost, "Respawn as a ghost.");
	RegConsoleCmd("sm_unghost", CMD_Unghost, "Return to spectator.");
	RegConsoleCmd("sm_unredie", CMD_Unghost, "Return to spectator.");
	RegConsoleCmd("sm_rmenu", CMD_GhostMenu, "Display player menu.");
	RegAdminCmd("sm_isghost", CMD_IsGhost, ADMFLAG_KICK, "Returns if player is a Ghost, also used for the Admin Menu");
	
	for (int i = 0; i <= MaxClients; i++)
	if (IsValidClient(i))
		OnClientPutInServer(i);
}

// Natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Ghost_IsGhost", Native_IsGhost);
	return APLRes_Success;
}

public int Native_IsGhost(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_bIsGhost[client];
}

public void OnClientCookiesCached(int client)
{
	char buffer[12];
	
	GetClientCookie(client, g_hBannedCookie, buffer, sizeof(buffer));
	if (StrEqual(buffer, ""))
	{
		SetClientCookie(client, g_hBannedCookie, "0");
	}
	
	GetClientCookie(client, g_hViewPlayersCookie, buffer, sizeof(buffer));
	if (StrEqual(buffer, ""))
	{
		SetClientCookie(client, g_hViewPlayersCookie, "1");
	}
}

public void OnMapStart()
{
	PrecacheModel("models/props/cs_militia/bottle02.mdl");
}

public void OnClientPutInServer(int client)
{
	if (IsValidClient(client))
	{
		g_iLastUsedCommand[client] = 0;
		g_bIsGhost[client] = false;
		g_bBlockSounds[client] = false;
		g_bBhopEnabled[client] = false;
		g_bSpeedEnabled[client] = false;
		g_bNoclipEnabled[client] = false;
		g_fSaveLocation[client] = view_as<float>( { -1.0, -1.0, -1.0 } );
		
		if (g_cGhostBhop.BoolValue)
			SendConVarValue(client, sv_autobunnyhopping, "0");
		if (g_cGhostSpeed.BoolValue)
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
public Action CMD_Ghost(int client, int args)
{
	if (!g_cPluginEnabled.BoolValue)
	{
		ReplyToCommand(client, "%s %sGhost%s has been temporarily disabled on this server.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	if (!AreClientCookiesCached(client))
	{
		ReplyToCommand(client, "%s Client preferences haven't loaded yet! Try again.", CHAT_PREFIX);
		return Plugin_Handled;
	}
	
	if (g_bPluginBlocked)
	{
		ReplyToCommand(client, "%s Please wait for the round to begin.", CHAT_PREFIX);
		return Plugin_Handled;
	}
	
	if (GameRules_GetProp("m_bWarmupPeriod"))
	{
		ReplyToCommand(client, "%s %sGhost%s is disabled during warmup.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client))
	{
		ReplyToCommand(client, "%s You must be a valid client in order to use %sGhost%s.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	if (IsPlayerAlive(client))
	{
		ReplyToCommand(client, "%s You must be dead in order to use %sGhost%s.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	char buffer[12];
	GetClientCookie(client, g_hBannedCookie, buffer, sizeof(buffer));
	if (StringToInt(buffer))
	{
		ReplyToCommand(client, "%s You are currently %sbanned%s from using Ghost!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	int time = GetTime();
	if (time - g_iLastUsedCommand[client] < g_iCoolDownTimer)
	{
		ReplyToCommand(client, "%s Too many commands issued! Please wait %s%i seconds%s before using that command again.", CHAT_PREFIX, CHAT_ACCENT, g_iCoolDownTimer - (time - g_iLastUsedCommand[client]), CHAT_COLOR);
		return Plugin_Handled;
	}
	
	Ghost(client);
	ShowPlayerMenu(client);
	g_iLastUsedCommand[client] = time;
	return Plugin_Handled;
}

public Action CMD_Unghost(int client, int args)
{
	if (!g_cPluginEnabled.BoolValue)
	{
		ReplyToCommand(client, "%s %sGhost%s has been temporarily disabled on this server.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	if (!g_bIsGhost[client])
	{
		ReplyToCommand(client, "%s You must be a %sGhost%s to use this command.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
		return Plugin_Handled;
	}
	
	if (g_bPluginBlocked)
	{
		ReplyToCommand(client, "%s Please wait for the round to begin.", CHAT_PREFIX);
		return Plugin_Handled;
	}
	
	int time = GetTime();
	if (time - g_iLastUsedCommand[client] < g_iCoolDownTimer)
	{
		ReplyToCommand(client, "%s Too many commands issued! Please wait %s%i seconds%s before using that command again.", CHAT_PREFIX, CHAT_ACCENT, g_iCoolDownTimer - (time - g_iLastUsedCommand[client]), CHAT_COLOR);
		return Plugin_Handled;
	}
	
	Unghost(client);
	g_iLastUsedCommand[client] = time;
	return Plugin_Handled;
}

public Action CMD_GhostMenu(int client, int args)
{
	if (g_bIsGhost[client])
	{
		ShowPlayerMenu(client);
		ReplyToCommand(client, "%s Opening Menu...", CHAT_PREFIX);
	}
	else
	{
		ReplyToCommand(client, "%s You must be a %sGhost%s to use this command.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
	}
	return Plugin_Handled;
}

public Action CMD_IsGhost(int client, int args)
{
	if (args != 1)
	{
		Menu menu = new Menu(InPlayerMenuHandler);
		menu.SetTitle("Players in Ghost");
		
		for (int i = 0; i <= MaxClients; i++)
		{
			if (g_bIsGhost[i])
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
		ReplyToCommand(client, "%s Player %s%s%s was not found.", CHAT_PREFIX, CHAT_ACCENT, arg, CHAT_COLOR);
	}
	else
	{
		if (g_bIsGhost[target])
		{
			ShowAdminMenu(client, target);
			ReplyToCommand(client, "%s Player %N %sIS%s a Ghost.", CHAT_PREFIX, target, CHAT_ACCENT, CHAT_COLOR);
		}
		else
		{
			ReplyToCommand(client, "%s Player %N is %sNOT%s a Ghost.", CHAT_PREFIX, target, CHAT_ACCENT, CHAT_COLOR);
			
			char name[64];
			GetClientName(target, name, sizeof(name));
			
			Menu menu = new Menu(AdminMenuHandler);
			
			if (AreClientCookiesCached(client))
			{
				char buffer[12];
				GetClientCookie(target, g_hBannedCookie, buffer, sizeof(buffer));
				
				if (StringToInt(buffer))
				{
					menu.AddItem("mapban", "Unban player from using Ghost");
					Format(name, sizeof(name), "Player: %s (%i) [BANNED]", name, GetClientUserId(target));
				}
				else
				{
					menu.AddItem("mapban", "Ban player from using Ghost");
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
	
	if (g_bIsGhost[client])
	{
		g_bBhopEnabled[client] = false;
		g_bSpeedEnabled[client] = false;
		g_bNoclipEnabled[client] = false;
		
		if (g_cGhostBhop.BoolValue)
			SendConVarValue(client, sv_autobunnyhopping, "0");
		if (g_cGhostSpeed.BoolValue)
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
	
	PrintToChat(client, "%s Type %s/ghost%s to respawn as a ghost!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (IsValidClient(client))
	{
		g_bIsGhost[client] = false;
		g_bBlockSounds[client] = false;
		g_bBhopEnabled[client] = false;
		g_bSpeedEnabled[client] = false;
		g_bNoclipEnabled[client] = false;
		if (g_cGhostBhop.BoolValue)
			SendConVarValue(client, sv_autobunnyhopping, "0");
		if (g_cGhostSpeed.BoolValue)
			SendConVarValue(client, sv_enablebunnyhopping, "0");
		
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
	g_bPluginBlocked = false;
	
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
	g_bPluginBlocked = true;
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (g_bIsGhost[i] && IsValidClient(i))
		{
			g_bIsGhost[i] = false;
		}
	}
}

// Timers
public Action Timer_ResetValue(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	g_bIsGhost[client] = false;
	return Plugin_Stop;
}


public Action Timer_ChatAdvert(Handle timer)
{
	if (g_cChatAdverts.BoolValue)
		PrintToChatAll("%s This server is running %sGhost%s! Type %s/ghost%s", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR, CHAT_ACCENT, CHAT_COLOR);
	
	return Plugin_Continue;
}


// SDKHooks
public Action Hook_SetTransmit_Player(int entity, int client)
{
	// View other ghosts
	if (g_bIsGhost[client] && g_bIsGhost[entity] && entity != client)
		return Plugin_Continue;
	
	// Hide ghosts from alive players.
	if (!g_bIsGhost[client] && g_bIsGhost[entity])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

// Disable ghosts from interacting with world by touch
public Action BlockOnTouch(int entity, int client)
{
	if (client && client <= MaxClients && g_bIsGhost[client])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

// Teleport a ghost to the destination position of a trigger_teleport on touch.
// This is done so ghosts do not interact with the world but still retain functionality.
public Action FakeTriggerTeleport(int entity, int client)
{
	if (client && client <= MaxClients && g_bIsGhost[client])
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
	if (g_cGhostBhop.BoolValue)
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
	
	if (g_cGhostSpeed.BoolValue)
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

// Disable weapons for ghosts
public Action Hook_WeaponCanUse(int client, int weapon)
{
	if (g_bIsGhost[client])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

// Plugin Functions
public void Ghost(int client)
{
	g_bBlockSounds[client] = true;
	g_bIsGhost[client] = false; // This is done so the player can pick up their spawned weapons to remove them.
	CS_RespawnPlayer(client);
	
	// Set values that were reset onplayerspawn
	g_bIsGhost[client] = true;
	g_bBlockSounds[client] = true;
	
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
	
	if (g_cGhostBhop.BoolValue)
	{
		g_bBhopEnabled[client] = true;
		SendConVarValue(client, sv_autobunnyhopping, "1");
	}
	else
	{
		g_bBhopEnabled[client] = false;
		SendConVarValue(client, sv_autobunnyhopping, "0");
	}
	
	// Make player turn into a "ghost"
	SetEntityModel(client, "models/props/cs_militia/bottle02.mdl"); // Set the playermodel to a small item in order to not block buttons, knife swings or bullets.
	SetEntProp(client, Prop_Send, "m_lifeState", 1);
	SetEntData(client, FindSendPropInfo("CBaseEntity", "m_CollisionGroup"), 2, 4, true);
	SetEntProp(client, Prop_Data, "m_ArmorValue", 0);
	SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
	
	ReplyToCommand(client, "%s Respawned as a %sghost%s.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
}

public void Unghost(int client)
{
	if (g_bIsGhost[client])
	{
		SetEntProp(client, Prop_Send, "m_lifeState", 0);
		SetEntProp(client, Prop_Data, "m_iFrags", GetClientFrags(client) + 1);
		SetEntProp(client, Prop_Data, "m_iDeaths", GetClientDeaths(client) - 1);
		ForcePlayerSuicide(client);
		
		ReplyToCommand(client, "%s Returned to %sspectator%s.", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
	}
}

// Menu Handlers
public int PlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		if (g_bIsGhost[param1])
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
						PrintToChat(param1, "%s Teleported to your saved location!", CHAT_PREFIX);
					}
					else
					{
						PrintToChat(param1, "%s Save a location first!", CHAT_PREFIX);
					}
				}
				case 2:
				{
					GetClientAbsOrigin(param1, g_fSaveLocation[param1]);
					PrintToChat(param1, "%s Saved Location!", CHAT_PREFIX);
				}
				case 3:
				{
					if (g_cGhostNoclip.BoolValue)
					{
						if (g_bNoclipEnabled[param1])
						{
							SetEntityMoveType(param1, MOVETYPE_WALK);
							g_bNoclipEnabled[param1] = false;
							PrintToChat(param1, "%s Disabled %sNoclip%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
						else
						{
							SetEntityMoveType(param1, MOVETYPE_NOCLIP);
							g_bNoclipEnabled[param1] = true;
							PrintToChat(param1, "%s Enabled %sNoclip%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
					}
					else
					{
						SetEntityMoveType(param1, MOVETYPE_WALK);
					}
				}
				case 4:
				{
					if (g_cGhostBhop.BoolValue)
					{
						if (g_bBhopEnabled[param1])
						{
							SendConVarValue(param1, sv_autobunnyhopping, "0");
							g_bBhopEnabled[param1] = false;
							PrintToChat(param1, "%s Disabled %sBhop%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
						else
						{
							SendConVarValue(param1, sv_autobunnyhopping, "1");
							g_bBhopEnabled[param1] = true;
							PrintToChat(param1, "%s Enabled %sBhop%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
					}
				}
				case 5:
				{
					if (g_cGhostSpeed.BoolValue)
					{
						if (g_bSpeedEnabled[param1])
						{
							SendConVarValue(param1, sv_enablebunnyhopping, "0");
							g_bSpeedEnabled[param1] = false;
							PrintToChat(param1, "%s Disabled %sUnlimited Speed%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
						else
						{
							SendConVarValue(param1, sv_enablebunnyhopping, "1");
							g_bSpeedEnabled[param1] = true;
							PrintToChat(param1, "%s Enabled %sUnlimited Speed%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
					}
				}
				case 6:
				{
					if (AreClientCookiesCached(param1))
					{
						char buffer[12];
						GetClientCookie(param1, g_hViewPlayersCookie, buffer, sizeof(buffer));
						
						if (StringToInt(buffer))
						{
							SetClientCookie(param1, g_hViewPlayersCookie, "0");
							PrintToChat(param1, "%s Ghosts are now %shidden%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
						else
						{
							SetClientCookie(param1, g_hViewPlayersCookie, "1");
							PrintToChat(param1, "%s Ghosts are now %sunhidden%s!", CHAT_PREFIX, CHAT_ACCENT, CHAT_COLOR);
						}
					}
					else
					{
						PrintToChat(param1, "%s You're settings haven't loaded yet. Try again.", CHAT_PREFIX);
					}
				}
				case 9:
				{
					return;
				}
			}
			ShowPlayerMenu(param1);
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

public int InPlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		int player = StringToInt(info);
		if (IsValidClient(player))
			ShowAdminMenu(param1, player);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int AdminMenuHandler(Menu menu, MenuAction action, int param1, int param2)
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
				PrintToChat(param1, "%s Teleported to %s%N%s.", CHAT_PREFIX, CHAT_ACCENT, player, CHAT_COLOR);
				ShowAdminMenu(param1, player);
			}
			else if (StrEqual(info, "unghost"))
			{
				Unghost(player);
				PrintToChatAll("%s %s%N %sreturned %s%N%s to spectator.", CHAT_PREFIX, CHAT_ACCENT, param1, CHAT_COLOR, CHAT_ACCENT, player, CHAT_COLOR);
			}
			
			else if (StrEqual(info, "mapban"))
			{
				if (AreClientCookiesCached(param1))
				{
					char sBuffer[12];
					GetClientCookie(player, g_hBannedCookie, sBuffer, sizeof(sBuffer));
					
					if (StringToInt(sBuffer))
					{
						SetClientCookie(player, g_hBannedCookie, "0");
						PrintToChatAll("%s %s%N%s unbanned %s%N%s from Ghost!", CHAT_PREFIX, CHAT_ACCENT, param1, CHAT_COLOR, CHAT_ACCENT, player, CHAT_COLOR);
					}
					else
					{
						Unghost(player);
						SetClientCookie(player, g_hBannedCookie, "1");
						PrintToChatAll("%s %s%N%s banned %s%N%s from Ghost!", CHAT_PREFIX, CHAT_ACCENT, param1, CHAT_COLOR, CHAT_ACCENT, player, CHAT_COLOR);
					}
				}
				else
				{
					PrintToChat(param1, "%s Client preferences haven't loaded yet! Try again.", CHAT_PREFIX);
				}
			}
		}
		else
		{
			PrintToChat(param1, "%s Fatal Regex error! Please try again.", CHAT_PREFIX);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void ShowPlayerMenu(int client)
{
	Panel panel = CreatePanel();
	panel.SetTitle("Ghost Menu [sm_rmenu]");
	
	panel.DrawItem("Teleport");
	panel.DrawItem("Checkpoint");
	
	panel.DrawText(" ");
	if (g_cGhostNoclip.BoolValue)
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
	
	if (g_cGhostBhop.BoolValue)
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
	
	if (g_cGhostSpeed.BoolValue)
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
		char buffer[12];
		GetClientCookie(client, g_hViewPlayersCookie, buffer, sizeof(buffer));
	}
	
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawText(" ");
	
	panel.DrawItem("Exit");
	panel.Send(client, PlayerMenuHandler, MENU_TIME_FOREVER);
	delete panel;
}

public void ShowAdminMenu(int client, int player)
{
	char name[64];
	GetClientName(player, name, sizeof(name));
	
	Menu menu = new Menu(AdminMenuHandler);
	menu.AddItem("teleport", "Teleport to Player");
	menu.AddItem("unghost", "Unghost Player");
	
	if (AreClientCookiesCached(client))
	{
		char buffer[12];
		GetClientCookie(player, g_hBannedCookie, buffer, sizeof(buffer));
		
		if (StringToInt(buffer))
		{
			Format(name, sizeof(name), "Player: %s (%i) [BANNED]", name, GetClientUserId(player));
			menu.SetTitle(name);
			menu.AddItem("mapban", "Unban player from Ghost");
		}
		else
		{
			Format(name, sizeof(name), "Player: %s (%i)", name, GetClientUserId(player));
			menu.SetTitle(name);
			menu.AddItem("mapban", "Ban player from Ghost");
		}
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public Action OnPlayerRunCmd(int client, int & buttons, int & impulse, float vel[3], float angles[3], int & weapon, int & subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (g_bIsGhost[client])
	{
		buttons &= ~IN_USE; // Block +use
		
		if (g_cGhostNoclip.BoolValue)
		{
			// Ghosts can hold reload (R) to use noclip
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