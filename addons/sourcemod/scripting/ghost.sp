/**
 * Ghost - Allow players to respawn as Ghost when they die.
 *
 * Copyright (C) 2020  Extacy
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

#pragma newdecls required
#pragma semicolon 1

// Plugin ConVars
ConVar g_cPluginEnabled;
ConVar g_cUnghostEnabled;

ConVar g_cBhopServer;

ConVar g_cGhostBhop;
ConVar g_cGhostNoclip;

ConVar g_cChatAdverts;
ConVar g_cChatAdvertsInterval;

// CSGO ConVars
ConVar sv_autobunnyhopping;

// Plugin Variables
bool g_bIsGhost[MAXPLAYERS + 1]; // Current players that are a Ghost
bool g_bSpawning[MAXPLAYERS + 1]; // Ghosts that are spawning in
bool g_bBhopEnabled[MAXPLAYERS + 1]; // Ghosts that have Bhop Enabled.
bool g_bNoclipEnabled[MAXPLAYERS + 1]; // Ghosts with noclip enabled
bool g_bPluginBlocked; // Disable the use of Ghost during freezetime and when the round is about to end.

int g_iLastUsedCommand[MAXPLAYERS + 1]; // Array of clients and the time they last used a command. (Used for cooldown.)
int g_iCoolDownTimer = 5; // How long, in seconds, should the cooldown between commands be
int g_iLastButtons[MAXPLAYERS + 1]; // Last used button (+use, +reload etc) for ghosts. - Used for noclip

public Plugin myinfo = 
{
	name = "Ghost", 
	author = "Extacy", 
	description = "Allow players to respawn as Ghost when they die.", 
	version = "1.0", 
	url = "https://github.com/Extacy/Ghost/"
};

public void OnPluginStart()
{
	AutoExecConfig(true, "ghost");

	LoadTranslations("ghost.phrases");

	g_cPluginEnabled = CreateConVar("sm_ghost_enabled", "1", "Set whether Ghost is enabled on the server.");
	g_cUnghostEnabled = CreateConVar("sm_ghost_unghost_enabled", "1", "Set whether !unghost and !unredie is enabled on the server.");
	
	g_cBhopServer = CreateConVar("sm_ghost_bhop_server", "0", "If you have sv_autobunnyhopping 1 set this to 1. (Resets this convar on spawn)");
	
	g_cGhostBhop = CreateConVar("sm_ghost_bhop", "1", "Set whether ghosts can autobhop.");
	g_cGhostNoclip = CreateConVar("sm_ghost_noclip", "1", "Set whether ghosts can noclip.");

	g_cChatAdverts = CreateConVar("sm_ghost_adverts", "1", "Set whether chat adverts are enabled.");
	g_cChatAdvertsInterval = CreateConVar("sm_ghost_adverts_interval", "120.0", "Interval (in seconds) of chat adverts.");
	
	sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
	
	HookEvent("round_start", Event_PreRoundStart, EventHookMode_Pre);
	HookEvent("round_end", Event_PreRoundEnd, EventHookMode_Pre);
	HookEvent("player_death", Event_PrePlayerDeath, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn);

	HookEntityOutput("func_door", "OnBlockedClosing", OnDoorBlocked);
	HookEntityOutput("func_door_rotating", "OnBlockedClosing", OnDoorBlocked);

	HookUserMessage(GetUserMessageId("TextMsg"), RemoveCashRewardMessage, true);
	
	AddNormalSoundHook(OnNormalSoundPlayed);
	
	CreateTimer(g_cChatAdvertsInterval.FloatValue, Timer_ChatAdvert, _, TIMER_REPEAT);
	
	RegConsoleCmd("sm_ghost", CMD_Ghost, "Respawn as a ghost.");
	RegConsoleCmd("sm_redie", CMD_Ghost, "Respawn as a ghost.");
	RegConsoleCmd("sm_unghost", CMD_Unghost, "Return to spectator.");
	RegConsoleCmd("sm_unredie", CMD_Unghost, "Return to spectator.");
	RegConsoleCmd("sm_rmenu", CMD_GhostMenu, "Display player menu.");
	
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
	return (g_bIsGhost[client] || g_bSpawning[client]);
}

public void OnClientPutInServer(int client)
{
	if (IsValidClient(client))
	{
		g_iLastUsedCommand[client] = 0;
		g_bIsGhost[client] = false;
		g_bSpawning[client] = false;
		g_bBhopEnabled[client] = false;
		g_bNoclipEnabled[client] = false;
		
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
	
	if (StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_YouGotCash") 
		|| StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_TeammateGotCash")
		|| StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_EnemyGotCash"))
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
		CPrintToChat(client, "%t %t", "ChatTag", "GhostDisabled");
		return Plugin_Handled;
	}
	
	if (g_bPluginBlocked)
	{
		CPrintToChat(client, "%t %t", "ChatTag", "WaitForNextRound");
		return Plugin_Handled;
	}
	
	if (GameRules_GetProp("m_bWarmupPeriod"))
	{
		CPrintToChat(client, "%t %t", "ChatTag", "WarmupDisabled");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client))
	{
		CPrintToChat(client, "%t %t", "ChatTag", "NotValidClient");
		return Plugin_Handled;
	}
	
	if (IsPlayerAlive(client))
	{
		CPrintToChat(client, "%t %t", "ChatTag", "NotDead");
		return Plugin_Handled;
	}
	
	int time = GetTime();
	if (time - g_iLastUsedCommand[client] < g_iCoolDownTimer)
	{
		CPrintToChat(client, "%t %t", "ChatTag", "CommandCooldown", g_iCoolDownTimer - (time - g_iLastUsedCommand[client]));
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
		CPrintToChat(client, "%t %t", "ChatTag", "GhostDisabled");
		return Plugin_Handled;
	}
	
	if (!g_cUnghostEnabled.BoolValue)
	{
		CPrintToChat(client, "%t %t", "ChatTag", "UnghostDisabled");
		return Plugin_Handled;
	}
	
	if (!g_bIsGhost[client])
	{
		CPrintToChat(client, "%t %t", "ChatTag", "NotGhost");
		return Plugin_Handled;
	}
	
	if (g_bPluginBlocked)
	{
		CPrintToChat(client, "%t %t", "ChatTag", "WaitForNextRound");
		return Plugin_Handled;
	}
	
	int time = GetTime();
	if (time - g_iLastUsedCommand[client] < g_iCoolDownTimer)
	{
		CPrintToChat(client, "%t %t", "ChatTag", "CommandCooldown", g_iCoolDownTimer - (time - g_iLastUsedCommand[client]));
		return Plugin_Handled;
	}
	
	Unghost(client);
	g_iLastUsedCommand[client] = time;
	return Plugin_Handled;
}

public Action CMD_GhostMenu(int client, int args)
{
	if (!g_bIsGhost[client])
	{
		CPrintToChat(client, "%t %t", "ChatTag", "NotGhost");
		return Plugin_Handled;
	}

	ShowPlayerMenu(client);
	CPrintToChat(client, "%t %t", "ChatTag", "OpeningMenu");
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
		g_bNoclipEnabled[client] = false;

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
	
	CPrintToChat(client, "%t %t", "ChatTag", "DeathMsg");
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClient(client))
	{
		g_bIsGhost[client] = false;
		g_bNoclipEnabled[client] = false;

		if (g_cBhopServer.BoolValue)
		{
			g_bBhopEnabled[client] = true;
			sv_autobunnyhopping.ReplicateToClient(client, "1");
		}
		else
		{
			g_bBhopEnabled[client] = false;
			sv_autobunnyhopping.ReplicateToClient(client, "0");
		}
	}
}

public Action OnNormalSoundPlayed(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
	if (IsValidClient(entity) && (g_bSpawning[entity] || g_bIsGhost[entity]))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Event_PreRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bPluginBlocked = false;
	
	char movingEntities[][] =  { "func_door", "func_door_rotating", "func_tanktrain", "func_tracktrain", "func_rotating" };
	for (int i = 0; i <= sizeof(movingEntities) - 1; i++)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, movingEntities[i])) != -1)
		{
			SDKHookEx(ent, SDKHook_EndTouch, RespawnOnTouch);
			SDKHookEx(ent, SDKHook_StartTouch, RespawnOnTouch);
			SDKHookEx(ent, SDKHook_Touch, RespawnOnTouch);
		}
	}
	
	char otherEntities[][] =  { "func_breakable", "func_breakable_surf", "func_button", "trigger_hurt", "trigger_multiple", "trigger_once" };
	for (int i = 0; i <= sizeof(otherEntities) - 1; i++)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, otherEntities[i])) != -1)
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
	{
		CPrintToChatAll("%t %t", "ChatTag", "Advert");
	}
	
	return Plugin_Continue;
}

// Disable ghosts from interacting with world by touch
public Action RespawnOnTouch(int entity, int client)
{
	if (IsValidClient(client) && g_bIsGhost[client])
	{
		Ghost(client);
		
		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));
		
		CPrintToChat(client, "%t %t", "ChatTag", "RespawnOnTouch", classname);
		return Plugin_Handled;
	}
		
	return Plugin_Continue;
}

public Action BlockOnTouch(int entity, int client)
{
	if (IsValidClient(client) && g_bIsGhost[client])
	{
		return Plugin_Handled;
	}
	
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

public Action Hook_WeaponCanUse(int client, int weapon)
{
	if (g_bIsGhost[client])
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action OnDoorBlocked(const char[] output, int caller, int activator, float delay)
{
	if (g_bIsGhost[activator])
	{
		char classname[64], targetname[64];
		GetEntPropString(caller, Prop_Send, "m_iName", targetname, sizeof(targetname));
		GetEntityClassname(caller, classname, sizeof(classname));

		DataPack pack = new DataPack();
		CreateDataTimer(0.1, Timer_ForceClose, pack);
		pack.WriteCell(activator);
		pack.WriteCell(caller);
		pack.WriteString(classname);
		pack.WriteString(targetname);
		pack.WriteString(output);
	}
}

public Action Timer_ForceClose(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	int entity = pack.ReadCell();
	char classname[64], targetname[64], output[64];
	pack.ReadString(classname, sizeof(classname));
	pack.ReadString(targetname, sizeof(targetname));
	pack.ReadString(output, sizeof(output));

	if (StrEqual(targetname, ""))
	{
		AcceptEntityInput(entity, "Close");
		CPrintToChat(client, "%t %t", "ChatTag", "RespawnOnBlock");

		Ghost(client);
	}
	else
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
		{
			char buffer[64];
			GetEntPropString(ent, Prop_Send, "m_iName", buffer, sizeof(buffer));
			if (StrEqual(targetname, buffer))
			{
				AcceptEntityInput(ent, "Close");
				CPrintToChat(client, "%t %t", "ChatTag", "RespawnOnBlock");
				Ghost(client);
			}
		}
	}
}

// Plugin Functions
public void Ghost(int client)
{
	g_bSpawning[client] = true;
	g_bIsGhost[client] = false; // This is done so the player can pick up their spawned weapons to remove them.
	CS_RespawnPlayer(client);
	
	// Set values that were reset onplayerspawn
	g_bIsGhost[client] = true;
	g_bSpawning[client] = false;
	
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

	// Make player turn into a "ghost"
	SetEntProp(client, Prop_Send, "m_lifeState", 1);
	SetEntData(client, FindSendPropInfo("CBaseEntity", "m_nSolidType"), 5, 4, true); // SOLID_CUSTOM
	SetEntProp(client, Prop_Data, "m_ArmorValue", 0);
	SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
	
	CPrintToChat(client, "%t %t", "ChatTag", "Ghost");
}

public void Unghost(int client)
{
	if (g_bIsGhost[client])
	{
		SetEntProp(client, Prop_Send, "m_lifeState", 0);
		SetEntProp(client, Prop_Data, "m_iFrags", GetClientFrags(client) + 1);
		SetEntProp(client, Prop_Data, "m_iDeaths", GetClientDeaths(client) - 1);
		ForcePlayerSuicide(client);
		
		CPrintToChat(client, "%t %t", "ChatTag", "Unghost");
	}
}

// Menu Handlers
public int PlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	static float vSavedLocation[MAXPLAYERS + 1][3];

	if (action == MenuAction_Select)
	{
		if (g_bIsGhost[param1])
		{
			switch (param2)
			{
				case 1:
				{
					GetClientAbsOrigin(param1, vSavedLocation[param1]);
					CPrintToChat(param1, "%t %t", "ChatTag", "SavedLocation");
				}
				case 2:
				{
					if (IsVectorZero(vSavedLocation[param1]))
					{
						CPrintToChat(param1, "%t %t", "ChatTag", "SaveLocationFirst");
					}
					else
					{
						TeleportEntity(param1, vSavedLocation[param1], NULL_VECTOR, view_as<float>({ -1.0, -1.0, -1.0 }));
						CPrintToChat(param1, "%t %t", "ChatTag", "TeleportedToLocation");
					}
				}
				case 3:
				{
					if (g_cGhostNoclip.BoolValue)
					{
						if (g_bNoclipEnabled[param1])
						{
							SetEntityMoveType(param1, MOVETYPE_WALK);
							g_bNoclipEnabled[param1] = false;
							CPrintToChat(param1, "%t %t", "ChatTag", "DisabledNoclip");
						}
						else
						{
							SetEntityMoveType(param1, MOVETYPE_NOCLIP);
							g_bNoclipEnabled[param1] = true;
							CPrintToChat(param1, "%t %t", "ChatTag", "EnabledNoclip");
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
							g_bBhopEnabled[param1] = false;
							sv_autobunnyhopping.ReplicateToClient(param1, "0");
							CPrintToChat(param1, "%t %t", "ChatTag", "DisabledBhop");
						}
						else
						{
							g_bBhopEnabled[param1] = true;
							sv_autobunnyhopping.ReplicateToClient(param1, "1");
							CPrintToChat(param1, "%t %t", "ChatTag", "EnabledBhop");
						}
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

public void ShowPlayerMenu(int client)
{
	Panel panel = CreatePanel();
	
	char buffer[32];

	Format(buffer, sizeof(buffer), "%T", "MenuTitle", client);
	panel.SetTitle(buffer);

	Format(buffer, sizeof(buffer), "%T", "MenuItemCheckpoint", client);
	panel.DrawItem(buffer);

	Format(buffer, sizeof(buffer), "%T", "MenuItemTeleport", client);
	panel.DrawItem(buffer);
	
	panel.DrawText(" ");
	if (g_cGhostNoclip.BoolValue)
	{
		if (g_bNoclipEnabled[client])
		{
			Format(buffer, sizeof(buffer), "[✔] %T", "MenuItemNoclip", client);
		}
		else
		{
			Format(buffer, sizeof(buffer), "[X] %T", "MenuItemNoclip", client);
		}
		
		panel.DrawItem(buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "[X] %T", "MenuItemNoclipDisabled", client);
		panel.DrawItem(buffer, ITEMDRAW_DISABLED);
	}
	
	if (g_cGhostBhop.BoolValue)
	{
		if (g_bBhopEnabled[client])
		{
			Format(buffer, sizeof(buffer), "[✔] %T", "MenuItemBhop", client);
		}
		else
		{
			Format(buffer, sizeof(buffer), "[X] %T", "MenuItemBhop", client);
		}
		
		panel.DrawItem(buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "[X] %T", "MenuItemBhopDisabled", client);
		panel.DrawItem(buffer, ITEMDRAW_DISABLED);
	}
	
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawItem("", ITEMDRAW_NOTEXT);
	panel.DrawText(" ");
	
	Format(buffer, sizeof(buffer), "%T", "MenuItemExit", client);
	panel.DrawItem(buffer);
	panel.Send(client, PlayerMenuHandler, MENU_TIME_FOREVER);
	delete panel;
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

		if (g_cGhostBhop.BoolValue && g_bBhopEnabled[client])
		{
			// Based off AbNeR's bhop code
			if (buttons & IN_JUMP)
			{
				if (GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1 && !(GetEntityMoveType(client) & MOVETYPE_LADDER) && !(GetEntityFlags(client) & FL_ONGROUND))
				{
					SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
					buttons &= ~IN_JUMP;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

// Stocks
stock bool IsValidClient(int client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	if (IsFakeClient(client)) return false;
	if (IsClientSourceTV(client)) return false;
	return IsClientInGame(client);
}

stock bool IsVectorZero(float vec[3])
{
	return (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0);
}