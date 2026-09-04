#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#undef REQUIRE_PLUGIN
#include <mapchooser>
#define REQUIRE_PLUGIN

#include "warmod_manager/globals.sp"
#include "warmod_manager/helpers.sp"
#include "warmod_manager/captains.sp"
#include "warmod_manager/leaver_system.sp"
#include "warmod_manager/ready_system.sp"
#include "warmod_manager/hostname.sp"
#include "warmod_manager/votestop.sp"
#include "warmod_manager/sourcebans_db.sp"

public Plugin myinfo =
{
    name = "WarMod Manager",
    description = "Advanced Competitive Match Manager for CS:S v34",
    author = "woobbie",
    version = "2.0.0",
    url = "https://github.com/Woobb1e"
};

// -------------------------------------------------------------------
// Forward declarations for internal helpers
// -------------------------------------------------------------------
void Cvars_OnPluginStart();
void Cvars_OnAllPluginsLoaded();
void Cvars_OnConfigsExecuted();
void Forwards_OnPluginStart();
void Natives_AskPluginLoad2();
void BuildState();
void DumpStatus(bool log);

// -------------------------------------------------------------------
// AskPluginLoad2 - library + natives + optional
// -------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("warmod_manager");
    Natives_AskPluginLoad2();

    MarkNativeAsOptional("CanMapChooserStartVote");
    MarkNativeAsOptional("InitiateMapChooserVote");

    return APLRes_Success;
}

void Natives_AskPluginLoad2()
{
    CreateNative("Warmod_IsActivated", Native_IsActivated);
    CreateNative("Warmod_IsMatchLive", Native_IsMatchLive);
    CreateNative("Warmod_IsHalfTime", Native_IsHalfTime);
    CreateNative("Warmod_IsLast", Native_IsLast);
    CreateNative("Warmod_IsReady", Native_IsReady);
    CreateNative("Warmod_MarkAsReady", Native_MarkAsReady);
    CreateNative("Warmod_RemoveFromLast", Native_RemoveFromLast);
    CreateNative("Warmod_GetScore", Native_GetScore);
    CreateNative("Warmod_GetCaptain", Native_GetCaptain);
    CreateNative("Warmod_GetState", Native_GetState);
}

public int Native_IsActivated(Handle plugin, int numParams)
{
    return g_bActivated;
}

public int Native_IsMatchLive(Handle plugin, int numParams)
{
    return IsMatchLive;
}

public int Native_IsHalfTime(Handle plugin, int numParams)
{
    return IsHalfTime;
}

public int Native_IsLast(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients)
        ThrowNativeError(SP_ERROR_NATIVE, "Client index %d is invalid", client);
    if (!IsClientInGame(client))
        ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
    return g_hLasts.FindValue(client) != -1;
}

public int Native_IsReady(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients)
        ThrowNativeError(SP_ERROR_NATIVE, "Client index %d is invalid", client);
    if (!IsClientInGame(client))
        ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
    return IsReady[client] || b_joined[client];
}

public int Native_MarkAsReady(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients)
        ThrowNativeError(SP_ERROR_NATIVE, "Client index %d is invalid", client);
    if (!IsClientInGame(client))
        ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
    IsReady[client] = true;
    b_joined[client] = true;
    FakeClientCommand(client, "say /r");
    return 0;
}

public int Native_RemoveFromLast(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int idx = g_hLasts.FindValue(client);
    if (idx != -1)
    {
        g_hLasts.Erase(idx);
        return 1;
    }
    return 0;
}

public int Native_GetScore(Handle plugin, int numParams)
{
    int team = GetNativeCell(1);
    switch (team)
    {
        case 2: return score_1;
        case 3: return score_2;
        default: return 0;
    }
}

public int Native_GetCaptain(Handle plugin, int numParams)
{
    int team = GetNativeCell(1);
    switch (team)
    {
        case 2: return captain_t;
        case 3: return captain_ct;
        default: return 0;
    }
}

public int Native_GetState(Handle plugin, int numParams)
{
    return view_as<int>(WMSate);
}

// -------------------------------------------------------------------
// Plugin lifecycle
// -------------------------------------------------------------------
public void OnPluginStart()
{
    // Offsets
    g_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
    if (g_iAccount == -1)
        SetFailState("Failed to find CCSPlayer::m_iAccount offset");

    BuildPath(Path_SM, s_LogFile, sizeof(s_LogFile), "logs/warmod_manager.log");
    BuildPath(Path_SM, s_DumpFile, sizeof(s_DumpFile), "logs/warmod_manager.dump");

    LoadTranslations("warmod.phrases");

    Forwards_OnPluginStart();
    Cvars_OnPluginStart();
    Hostname_OnPluginStart();
    Votestop_OnPluginStart();
    Captains_OnPluginStart();
    LeaveSystem_OnPluginStart();
    Sourcebans_OnPluginStart();
    ReadySystem_OnPluginStart();
    Forcestart_OnPluginStart();
    WThrow_OnPluginStart();

    HookEvent("round_end", OnRoundEnd, EventHookMode_Post);
    HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
    HookEvent("player_team", OnPlayerTeam, EventHookMode_Post);
    HookEvent("item_pickup", OnItemPickup, EventHookMode_Post);

    AddCommandListener(SayChat, "say");
    AddCommandListener(SayChat, "say_team");

    RegServerCmd("wmm_status", Command_Status, "Prints status of the plugin");
    RegServerCmd("wmm_status_dump", Command_StatusDump, "Dumps statuses to file");

    tv_enable = FindConVar("tv_enable");
    if (tv_enable != null)
        tv_enabled = tv_enable.BoolValue;

    h_CvarHostIp = FindConVar("hostip");
    h_CvarPort = FindConVar("hostport");
    if (h_CvarHostIp != null)
    {
        int longIp = h_CvarHostIp.IntValue;
        if (longIp != 0)
            FormatEx(s_hostip, sizeof(s_hostip), "%d.%d.%d.%d", (longIp >> 24) & 0xFF, (longIp >> 16) & 0xFF, (longIp >> 8) & 0xFF, longIp & 0xFF);
    }
    if (h_CvarPort != null)
        h_CvarPort.GetString(s_port, sizeof(s_port));

    // Initialize SourceTV tracking
    SourceTV = -1;

    // Handle already connected clients (late load)
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i))
        {
            OnClientConnected(i);
            if (IsClientInGame(i))
            {
                OnClientPutInServer(i);
                if (IsClientAuthorized(i))
                    OnClientPostAdminCheck(i);
            }
        }
    }
}

public void OnPluginEnd()
{
    Hostname_OnPluginEnd();
}

public void OnAllPluginsLoaded()
{
    wm_overtime = FindConVar("wm_overtime");
    if (LibraryExists("warmod"))
    {
        if (g_hSecondsTimer == null)
            g_hSecondsTimer = CreateTimer(1.0, OnEverySecond, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    Cvars_OnAllPluginsLoaded();
    Sourcebans_OnAllPluginsLoaded();

    StopMatch();
}

public Action OnEverySecond(Handle timer)
{
    ReadySystem_OnEverySecond();
    Captains_OnEverySecond();
    return Plugin_Continue;
}

public void OnMapStart()
{
    if (tv_enable != null)
        tv_enabled = tv_enable.BoolValue;

    WThrow_OnMapStart();
    ReadySystem_OnMapStart();
    score_1 = 0;
    score_2 = 0;
    IsMatchLive = false;
    IsHalfTime = false;
    b_Half = false;
    b_Overtime = false;
    Captains_OnMapStart();
    Votestop_OnMapStart();
    InitializeConfigParser();
    PrecacheModel("models/props_junk/watermelon01.mdl", true);
}

public void OnMapEnd()
{
    if (IsMatchLive)
    {
        BuildPlayers();
        IsMatchLive = false;
        StopMatch();
    }
    IsHalfTime = false;
    b_Overtime = false;
    Captains_OnMapEnd();
    LeaveSystem_OnMapEnd();
}

public void OnConfigsExecuted()
{
    Cvars_OnConfigsExecuted();
    Hostname_OnConfigsExecuted();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "warmod", false))
    {
        wm_overtime = FindConVar("wm_overtime");
        Cvars_OnAllPluginsLoaded();
        if (g_hSecondsTimer == null)
            g_hSecondsTimer = CreateTimer(1.0, OnEverySecond, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (StrEqual(name, "sourcebans", false) || StrEqual(name, "sourcebans++", false))
    {
        Sourcebans_OnLibraryAdded(name);
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "warmod", false))
    {
        wm_overtime = null;
        if (g_hSecondsTimer != null)
        {
            delete g_hSecondsTimer;
            g_hSecondsTimer = null;
        }
        // Reset warmod cvar handles
        g_h_active = null;
        g_h_show_info = null;
        g_h_min_ready = null;
        wm_max_rounds = null;
        wm_overtime_max_rounds = null;
        wm_auto_swap = null;
        wm_auto_swap_delay = null;
        IsMatchLive = false;
        IsHalfTime = false;
        g_warmod = false;
        i_min_ready = 10;
        i_max_rounds = 15;
        i_max_overtime_rounds = 3;
    }
    else if (StrEqual(name, "sourcebans", false) || StrEqual(name, "sourcebans++", false))
    {
        Sourcebans_OnLibraryRemoved(name);
    }
}

public void OnClientConnected(int client)
{
    if (tv_enabled && GetClientUserId(client) == 2)
    {
        SourceTV = client;
        return;
    }
    Votestop_OnClientConnected(client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    LeaveSystem_OnClientAuthorized(client, auth);
}

public void OnClientPutInServer(int client)
{
    if (tv_enabled && client == SourceTV)
        return;

    LeaveSystem_OnClientPutInServer(client);
    Captains_OnClientPutInServer(client);
    ReadySystem_OnClientPutInServer();
    Hostname_OnClientPutInServer();
    BuildState();
}

public void OnClientPostAdminCheck(int client)
{
    if (SourceTV == client)
        return;

    IsClientAdmin[client] = false;
    if (!IsFakeClient(client))
    {
        if (i_adminflags != 0)
            IsClientAdmin[client] = (GetUserFlagBits(client) & i_adminflags) != 0;
        else
            IsClientAdmin[client] = GetUserAdmin(client) != INVALID_ADMIN_ID;
    }
    Captains_OnClientPostAdminCheck(client);
    LeaveSystem_OnClientPostAdminCheck(client);
}

public void OnRebuildAdminCache(AdminCachePart part)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i))
            OnClientPostAdminCheck(i);
    }
}

public void OnClientDisconnect(int client)
{
    if (SourceTV == client)
        return;
    Captains_OnClientDisconnect(client);
    Votestop_OnClientDisconnect(client);
}

public void OnClientDisconnect_Post(int client)
{
    if (SourceTV == client)
    {
        SourceTV = -1;
        return;
    }
    IsClientAdmin[client] = false;
    Captains_OnClientDisconnect_Post(client);
    ReadySystem_OnClientDisconnect_Post(client);
    Hostname_OnClientDisconnect_Post();
    Forcestart_OnClientDisconnect_Post(client);
    BuildState();
}

// -------------------------------------------------------------------
// Forwards & Cvars
// -------------------------------------------------------------------
void Forwards_OnPluginStart()
{
    h_fwdOnActivated = new GlobalForward("Warmod_OnActivated", ET_Ignore, Param_String);
    h_fwdOnPlayerReconnected = new GlobalForward("Warmod_OnPlayerReconnected", ET_Ignore, Param_Cell);
    h_fwdOnPlayerReplaced = new GlobalForward("Warmod_OnPlayerReplaced", ET_Ignore, Param_Cell, Param_String);
    h_fwdOnPlayerLast = new GlobalForward("Warmod_OnPlayerLast", ET_Event, Param_Cell);
    h_fwdOnPlayerReplaceByCmd = new GlobalForward("Warmod_OnPlayerReplaceByCmd", ET_Event, Param_Cell, Param_Cell);
    h_fwdOnPlayerReplacedByCmd = new GlobalForward("Warmod_OnPlayerReplacedByCmd", ET_Ignore, Param_Cell, Param_Cell);
    h_fwdOnPlayerBan = new GlobalForward("Warmod_OnPlayerBan", ET_Event, Param_Cell, Param_String, Param_String, Param_String);
    h_fwdOnPlayerBanned = new GlobalForward("Warmod_OnPlayerBanned", ET_Ignore, Param_String, Param_String, Param_String, Param_String, Param_Cell);
    h_fwdOnMatchStart = new GlobalForward("Warmod_OnMatchStart", ET_Ignore, Param_Array, Param_Cell);
    h_fwdOnMatchEnd = new GlobalForward("Warmod_OnMatchEnd", ET_Ignore, Param_Cell, Param_Array, Param_Cell, Param_Array, Param_Cell);
}

void Cvars_OnPluginStart()
{
    CreateConVar("wm_manager_version", "2.0.0", "The plugin's version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_h_CvarAdminFlag = CreateConVar("wm_admin_immunity_flag", "b", "An admin flag for immunity of bans and lasts. Leave it empty for any flag or 0 to disable the immunity");
    g_h_CvarDebug = CreateConVar("wm_debug_enable", "0", "Enables debug mode.", _, true, 0.0, true, 1.0);
    g_h_CvarBanDisconnected = CreateConVar("wm_ban_disconnected", "1", "Ban players for disconnecting when match is live.", _, true, 0.0, true, 1.0);
    g_h_CvarBanIn = CreateConVar("wm_ban_in", "120", "How long a player has ability to reconnect to the server before be banned. In seconds", _, true, 0.0);
    g_h_CvarBanAnnounce = CreateConVar("wm_ban_announce", "1", "Announces to the chat about the ban.", _, true, 0.0, true, 1.0);
    g_h_CvarBanAdminsImmunity = CreateConVar("wm_ban_admins_immunity", "1", "Whether to enable immunity for admins against ban for leave", _, true, 0.0, true, 1.0);
    g_h_CvarBanTime = CreateConVar("wm_ban_time", "1440", "Ban time. In minutes", _, true, 0.0);
    g_h_CvarBanTimeExtend = CreateConVar("wm_ban_time_extend", "1440", "Ban time to extend for. Available only with Sourcebans", _, true, 0.0);
    g_h_CvarResetBanCount = CreateConVar("wm_ban_count_reset_in", "168", "In what time to reset a player's ban count (No ban time extension). In hours", _, true, 1.0);
    g_h_CvarBanAllowReplacements = CreateConVar("wm_allow_replacements", "1", "Allow players to leave a match without ban if he had been replaced by another player.", _, true, 0.0, true, 1.0);
    g_h_CvarBanAutoReplacements = CreateConVar("wm_auto_replacements", "0", "Auto replace disconnected player with a spectator.", _, true, 0.0, true, 1.0);
    g_h_AllowAsk = CreateConVar("wm_replace_allow_ask", "1", "Allows a player to ask a spectator to replace him to avoid banning", _, true, 0.0, true, 1.0);
    g_h_AskCommands = CreateConVar("wm_replace_ask_command", "ask", "Command to listen to. (ex. !ask, /ask, .ask)");
    g_h_CvarEnableLast = CreateConVar("wm_lasts_system_enable", "1", "Whether to enable lasts system. Last connected players can not be chosen through menu or be captain", _, true, 0.0, true, 1.0);
    g_h_CvarAdminImmuneToLast = CreateConVar("wm_lasts_system_immunity", "1", "Whether to enable immunity for admins to avoid marking <last player>.", _, true, 0.0, true, 1.0);
    g_h_CvarInitiateMapChoose = CreateConVar("wm_endmatch_votemap", "1", "Start vote for the next map at the end of a match.", _, true, 0.0, true, 1.0);
    g_h_CvarAskMenu = CreateConVar("wm_readysystem_askmenu", "1", "Should we ask players via menu whether to begin the match. Depends on wm_min_ready", _, true, 0.0, true, 1.0);
    g_h_CvarCaptainsMod = CreateConVar("wm_captains_enable", "1", "It will integrate the captains mode to easy start the mix", _, true, 0.0, true, 1.0);
    g_h_CvarCaptainsAutoSelectTime = CreateConVar("wm_captains_auto_select_time", "30", "How long to wait for captains before auto select them. 0 to disable and 1 to instant select", _, true, 0.0, true, 60.0);
    g_h_CvarCaptainsWThrow = CreateConVar("wm_captains_watermelon_throw", "0", "Enable captains watermelon throwing", _, true, 0.0, true, 1.0);
    g_h_CvarAutoHalfForceStart = CreateConVar("wm_autohalf_forcestart", "2", "If 0, to disable. If 1, force start on half time. If 2, force start when on the server wm_min_ready players. If 3, force auto-start after swap", _, true, 0.0, true, 3.0);
    h_MinPlayers = CreateConVar("wm_stop_min_players", "4", "Minimum players allowed to continue a match. Less than 2 to disable", _, true, 0.0, true, 64.0);
    g_h_CvarHostname = CreateConVar("wm_match_hostname_info", "1", "Allow the system to display current state of the match in the end of the hostname", _, true, 0.0, true, 1.0);
    g_h_CvarVoteStop = CreateConVar("wm_match_votestop", "1", "Allow players to vote for stopping a match.", _, true, 0.0, true, 1.0);
    g_h_CvarVoteStopNeeded = CreateConVar("wm_match_votestop_needed", "0.60", "Percentage of players needed to votestop (Def 60%)", _, true, 0.05, true, 1.0);
    g_h_CvarVoteStopCommand = CreateConVar("wm_match_votestop_command", "stop", "The commands a player must type to vote");

    // Cache initial values
    i_minplayers = h_MinPlayers.IntValue;
    i_bantime = g_h_CvarBanTime.IntValue;
    i_bantimeextend = g_h_CvarBanTimeExtend.IntValue;
    i_resetbancount = g_h_CvarResetBanCount.IntValue;
    i_forcestart = g_h_CvarAutoHalfForceStart.IntValue;
    i_autoselecttime = g_h_CvarCaptainsAutoSelectTime.IntValue;
    f_banin = g_h_CvarBanIn.FloatValue;
    f_votestopneeded = g_h_CvarVoteStopNeeded.FloatValue;
    b_initiatemapchoose = g_h_CvarInitiateMapChoose.BoolValue;
    b_bandisconnected = g_h_CvarBanDisconnected.BoolValue;
    b_banannounce = g_h_CvarBanAnnounce.BoolValue;
    b_ban_admins_immunity = g_h_CvarBanAdminsImmunity.BoolValue;
    b_allowask = g_h_AllowAsk.BoolValue;
    b_allowreplacements = g_h_CvarBanAllowReplacements.BoolValue;
    b_autoreplacements = g_h_CvarBanAutoReplacements.BoolValue;
    b_askmenu = g_h_CvarAskMenu.BoolValue;
    b_hostname = g_h_CvarHostname.BoolValue;
    b_captainsmod = g_h_CvarCaptainsMod.BoolValue;
    b_votestop = g_h_CvarVoteStop.BoolValue;
    b_captainswthrow = g_h_CvarCaptainsWThrow.BoolValue;
    b_use_last = g_h_CvarEnableLast.BoolValue;
    b_admin_immunity_of_last = g_h_CvarAdminImmuneToLast.BoolValue;
    b_debug = g_h_CvarDebug.BoolValue;

    char sAdminFlag[64];
    g_h_CvarAdminFlag.GetString(sAdminFlag, sizeof(sAdminFlag));
    int bytes;
    i_adminflags = ReadFlagString(sAdminFlag, bytes);
    g_h_CvarVoteStopCommand.GetString(s_votestopcommand, sizeof(s_votestopcommand));
    g_h_AskCommands.GetString(s_askcommands, sizeof(s_askcommands));

    HookConVarChange(h_MinPlayers, OnConVarChange);
    HookConVarChange(g_h_CvarBanTime, OnConVarChange);
    HookConVarChange(g_h_CvarBanTimeExtend, OnConVarChange);
    HookConVarChange(g_h_CvarResetBanCount, OnConVarChange);
    HookConVarChange(g_h_CvarAutoHalfForceStart, OnConVarChange);
    HookConVarChange(g_h_CvarBanIn, OnConVarChange);
    HookConVarChange(g_h_CvarInitiateMapChoose, OnConVarChange);
    HookConVarChange(g_h_CvarBanDisconnected, OnConVarChange);
    HookConVarChange(g_h_CvarBanAnnounce, OnConVarChange);
    HookConVarChange(g_h_CvarBanAdminsImmunity, OnConVarChange);
    HookConVarChange(g_h_AllowAsk, OnConVarChange);
    HookConVarChange(g_h_AskCommands, OnConVarChange);
    HookConVarChange(g_h_CvarBanAllowReplacements, OnConVarChange);
    HookConVarChange(g_h_CvarBanAutoReplacements, OnConVarChange);
    HookConVarChange(g_h_CvarAdminFlag, OnConVarChange);
    HookConVarChange(g_h_CvarVoteStop, OnConVarChange);
    HookConVarChange(g_h_CvarVoteStopNeeded, OnConVarChange);
    HookConVarChange(g_h_CvarVoteStopCommand, OnConVarChange);
    HookConVarChange(g_h_CvarHostname, OnConVarChange);
    HookConVarChange(g_h_CvarCaptainsMod, OnConVarChange);
    HookConVarChange(g_h_CvarCaptainsWThrow, OnConVarChange);
    HookConVarChange(g_h_CvarEnableLast, OnConVarChange);
    HookConVarChange(g_h_CvarAdminImmuneToLast, OnConVarChange);
    HookConVarChange(g_h_CvarCaptainsAutoSelectTime, OnConVarChange);
    HookConVarChange(g_h_CvarDebug, OnConVarChange);
    HookConVarChange(g_h_CvarAskMenu, OnConVarChange);

    i_min_ready = 10;
    AutoExecConfig(true, "warmod_manager", "warmod");
}

void Cvars_OnAllPluginsLoaded()
{
    g_h_active = FindConVar("wm_active");
    if (g_h_active != null)
    {
        g_warmod = g_h_active.BoolValue;
        g_h_active.AddChangeHook(OnWarmodConVarChange);
    }
    g_h_show_info = FindConVar("wm_show_info");
    g_h_min_ready = FindConVar("wm_min_ready");
    if (g_h_min_ready != null)
    {
        i_min_ready = g_h_min_ready.IntValue;
        g_h_min_ready.AddChangeHook(OnWarmodConVarChange);
    }
    wm_max_rounds = FindConVar("wm_max_rounds");
    if (wm_max_rounds != null)
    {
        i_max_rounds = wm_max_rounds.IntValue;
        wm_max_rounds.AddChangeHook(OnWarmodConVarChange);
    }
    wm_overtime_max_rounds = FindConVar("wm_overtime_max_rounds");
    if (wm_overtime_max_rounds != null)
    {
        i_max_overtime_rounds = wm_overtime_max_rounds.IntValue;
        wm_overtime_max_rounds.AddChangeHook(OnWarmodConVarChange);
    }
    wm_auto_swap = FindConVar("wm_auto_swap");
    wm_auto_swap_delay = FindConVar("wm_auto_swap_delay");
}

void Cvars_OnConfigsExecuted()
{
    // Ensure activated stays true (DRM bypass)
    g_bActivated = true;
    IsActivated = true;
}

public void OnWarmodConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_h_active)
        g_warmod = StringToInt(newValue) != 0;
    else if (convar == g_h_min_ready)
    {
        i_min_ready = StringToInt(newValue);
        Captains_OnClientPutInServer(0);
    }
    else if (convar == wm_max_rounds)
        i_max_rounds = StringToInt(newValue);
    else if (convar == wm_overtime_max_rounds)
        i_max_overtime_rounds = StringToInt(newValue);
}

public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == h_MinPlayers)
        i_minplayers = StringToInt(newValue);
    else if (convar == g_h_CvarBanTime)
        i_bantime = StringToInt(newValue);
    else if (convar == g_h_CvarBanTimeExtend)
        i_bantimeextend = StringToInt(newValue);
    else if (convar == g_h_CvarResetBanCount)
        i_resetbancount = StringToInt(newValue);
    else if (convar == g_h_CvarAutoHalfForceStart)
        i_forcestart = StringToInt(newValue);
    else if (convar == g_h_CvarCaptainsAutoSelectTime)
        i_autoselecttime = StringToInt(newValue);
    else if (convar == g_h_CvarBanIn)
        f_banin = StringToFloat(newValue);
    else if (convar == g_h_CvarInitiateMapChoose)
        b_initiatemapchoose = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarBanDisconnected)
        b_bandisconnected = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarBanAdminsImmunity)
        b_ban_admins_immunity = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarBanAnnounce)
        b_banannounce = StringToInt(newValue) != 0;
    else if (convar == g_h_AllowAsk)
        b_allowask = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarBanAllowReplacements)
        b_allowreplacements = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarBanAutoReplacements)
        b_autoreplacements = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarAskMenu)
        b_askmenu = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarDebug)
        b_debug = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarVoteStop)
        b_votestop = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarHostname)
        b_hostname = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarEnableLast)
        b_use_last = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarAdminImmuneToLast)
    {
        b_admin_immunity_of_last = StringToInt(newValue) != 0;
        Captains_ImmunityModeChange();
    }
    else if (convar == g_h_CvarCaptainsMod)
    {
        b_captainsmod = StringToInt(newValue) != 0;
        Captains_OnModeChange();
    }
    else if (convar == g_h_CvarCaptainsWThrow)
        b_captainswthrow = StringToInt(newValue) != 0;
    else if (convar == g_h_CvarVoteStopNeeded)
        f_votestopneeded = StringToFloat(newValue);
    else if (convar == g_h_CvarVoteStopCommand)
        strcopy(s_votestopcommand, sizeof(s_votestopcommand), newValue);
    else if (convar == g_h_AskCommands)
        strcopy(s_askcommands, sizeof(s_askcommands), newValue);
    else if (convar == g_h_CvarAdminFlag)
    {
        int bytes;
        i_adminflags = ReadFlagString(newValue, bytes);
        if (bytes == 0)
            i_adminflags = ReadFlagString("b", bytes);
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
                OnClientPostAdminCheck(i);
        }
    }
}

// -------------------------------------------------------------------
// Event handlers
// -------------------------------------------------------------------
public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_warmod || !IsMatchLive)
        return Plugin_Continue;

    int winnerTeam = event.GetInt("winner");
    if (winnerTeam == 2)
        score_1++;
    else if (winnerTeam == 3)
        score_2++;

    Hostname_OnRoundEnd();

    int totalRounds = score_1 + score_2;
    int maxRegularRounds = i_max_rounds * 2;

    // Check Halftime condition
    if (!b_Half && totalRounds == i_max_rounds)
    {
        b_Half = true;
        IsHalfTime = true;
        OnHalfTime();
        return Plugin_Continue;
    }

    // Check Overtime vs Match End conditions
    if (totalRounds >= maxRegularRounds)
    {
        if (score_1 == score_2)
        {
            // Tie -> Initiate Overtime Vote
            b_Overtime = true;
            CreateTimer(1.0, Timer_RunOvertimeVote, _, TIMER_FLAG_NO_MAPCHANGE);
        }
        else if (score_1 > i_max_rounds || score_2 > i_max_rounds)
        {
            // Winner reached threshold
            OnEndMatch();
        }
    }

    return Plugin_Continue;
}

public Action OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || IsFakeClient(client))
        return Plugin_Continue;

    char reason[128];
    event.GetString("reason", reason, sizeof(reason));
    LeaveSystem_OnPlayerDisconnect(client, reason);
    return Plugin_Continue;
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || SourceTV == client)
        return Plugin_Continue;
    Captains_OnPlayerSpawn(client);
    return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || client == SourceTV)
        return Plugin_Continue;
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (attacker == 0 || attacker == SourceTV)
        return Plugin_Continue;
    Captains_OnPlayerDeath(client, attacker, weapon);
    return Plugin_Continue;
}

public Action OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || client == SourceTV)
        return Plugin_Continue;
    int team = event.GetInt("team");
    LeaveSystem_OnPlayerTeam(client, team);
    Captains_OnPlayerTeam(client, team);
    ReadySystem_OnPlayerTeam(client, team);
    Forcestart_OnPlayerTeam(client, team);
    return Plugin_Continue;
}

public Action OnItemPickup(Event event, const char[] name, bool dontBroadcast)
{
    char weapon[64];
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0)
        return Plugin_Continue;
    event.GetString("item", weapon, sizeof(weapon));
    Captains_OnItemPickup(client, weapon);
    return Plugin_Continue;
}

public Action SayChat(int client, const char[] command, int argc)
{
    if (!g_warmod || client == 0 || IsFakeClient(client))
        return Plugin_Continue;

    char text[192];
    if (!GetCmdArgString(text, sizeof(text)))
        return Plugin_Continue;

    int start = 0;
    if (text[0] == '"')
    {
        text[strlen(text) - 1] = '\0';
        start = 1;
    }

    // Check for chat commands with ! . /
    if (text[start] == '!' || text[start] == '.' || text[start] == '/')
    {
        char cmd[64];
        int pos = start + 1;
        int len = 0;
        while (text[pos] != '\0' && text[pos] != ' ' && len < sizeof(cmd) - 1)
        {
            cmd[len++] = text[pos++];
        }
        cmd[len] = '\0';

        if (LeaveSystem_SayChat(client, cmd))
            return Plugin_Handled;
        if (ReadySystem_SayChat(client, cmd))
            return Plugin_Continue;
        if (Votestop_SayChat(client, cmd))
            return Plugin_Continue;
        return Plugin_Continue;
    }

    // Also check votestop without prefix handling (original passed full text)
    if (Votestop_SayChat(client, text[start]))
        return Plugin_Continue;

    return Plugin_Continue;
}

// -------------------------------------------------------------------
// Match lifecycle forwards (warmod)
// -------------------------------------------------------------------
public void OnLiveOn3()
{
    if (!IsMatchLive && !IsHalfTime)
    {
        score_1 = 0;
        score_2 = 0;
        int clients[MAXPLAYERS + 1];
        int numClients = 0;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                int team = GetClientTeam(i);
                if (team == 2 || team == 3)
                    clients[numClients++] = i;
            }
        }
        Call_StartForward(h_fwdOnMatchStart);
        Call_PushArray(clients, numClients);
        Call_PushCell(numClients);
        Call_Finish();
    }
    IsMatchLive = true;
    IsHalfTime = false;
    b_Half = false;
    Captains_OnLiveOn3();
    Hostname_OnLiveOn3();
    ReadySystem_OnLiveOn3();
    ForceStart_OnLiveOn3();
    if (b_debug)
        LogToFile(s_LogFile, "The match has started");
    BuildState();
}

public void OnResetMatch()
{
    if (IsMatchLive)
        BuildPlayers();
    score_1 = 0;
    score_2 = 0;
    Votestop_OnResetMatch();
    Captains_OnResetMatch();
    Hostname_OnResetMatch();
    ReadySystem_OnResetMatch();
    ForceStart_OnResetMatch();
    IsMatchLive = false;
    IsHalfTime = false;
    b_Half = false;
    b_Overtime = false;
    if (b_debug)
        LogToFile(s_LogFile, "The match has been reset");
    BuildState();
}

public void OnEndMatch()
{
    if (IsMatchLive)
        BuildPlayers();
    score_1 = 0;
    score_2 = 0;
    Votestop_OnEndMatch();
    Captains_OnEndMatch();
    Hostname_OnEndMatch();
    Mapchoose_OnEndMatch(false);
    LeaveSystem_OnEndMatch();
    ForceStart_OnEndMatch();
    ReadySystem_OnEndMatch();
    IsMatchLive = false;
    IsHalfTime = false;
    b_Half = false;
    b_Overtime = false;
    if (b_debug)
        LogToFile(s_LogFile, "The match has ended");
    BuildState();
}

void BuildPlayers()
{
    int numWinPlayers = 0;
    int numLoosePlayers = 0;
    int winnerTeam = 0;
    int winClients[MAXPLAYERS + 1];
    int looseClients[MAXPLAYERS + 1];

    if (score_1 > score_2)
        winnerTeam = 2;
    else if (score_1 < score_2)
        winnerTeam = 3;
    else
        winnerTeam = 1;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;
        int team = GetClientTeam(i);
        if (winnerTeam == 1)
        {
            if (team == 2 || team == 3)
                winClients[numWinPlayers++] = i;
        }
        else if (winnerTeam == team)
        {
            winClients[numWinPlayers++] = i;
        }
        else if (team == 2 || team == 3)
        {
            looseClients[numLoosePlayers++] = i;
        }
    }

    Call_StartForward(h_fwdOnMatchEnd);
    Call_PushCell(winnerTeam);
    Call_PushArray(winClients, numWinPlayers);
    Call_PushCell(numWinPlayers);
    Call_PushArray(looseClients, numLoosePlayers);
    Call_PushCell(numLoosePlayers);
    Call_Finish();
}

public void OnResetHalf()
{
    IsHalfTime = true;
    b_Half = true;
    Hostname_OnResetHalf();
    if (b_debug)
        LogToFile(s_LogFile, "Half match has been reset");
    BuildState();
}

public void OnHalfTime()
{
    IsHalfTime = true;
    Captains_OnHalfTime();
    Forcestart_OnHalfTime();
    if (b_debug)
        LogToFile(s_LogFile, "Half time reached");
    BuildState();
}

void BuildState()
{
    if (IsMatchLive)
        WMSate = WMState_Live;
    else if (GetClientsCount(4) >= i_min_ready)
        WMSate = WMState_Waiting;
    else
        WMSate = WMState_None;
}

// -------------------------------------------------------------------
// Commands
// -------------------------------------------------------------------
public Action Command_Status(int args)
{
    DumpStatus(false);
    return Plugin_Handled;
}

public Action Command_StatusDump(int args)
{
    DumpStatus(true);
    return Plugin_Handled;
}

void DumpStatus(bool log)
{
    char format[1024];
    char activatedStr[32];
    char dbStr[32];
    char liveStr[32];
    char halfStr[32];

    strcopy(activatedStr, sizeof(activatedStr), g_bActivated ? "activated" : "not activated");
    strcopy(dbStr, sizeof(dbStr), h_Database != null ? "available" : "unavailable");
    strcopy(liveStr, sizeof(liveStr), IsMatchLive ? "live" : "not live");
    strcopy(halfStr, sizeof(halfStr), IsHalfTime ? "half time" : "not half time");

    FormatEx(format, sizeof(format), "~~~~~~ DUMP ~~~~~~\n[Warmod Manager v%s]\n---\nStatus: %s\nPublic IP: %s %s\nPort: %s\nSourcebans is %s\nDatabase prefix: %s\nServer ident: %d\nMatch is %s\nHalf time is %s\nScore: %d - %d\nNumber of lasts: %d\nIn Game: %d\nIn Teams: %d\n---\n~~~~~~ DUMP ~~~~~~", WM_MANAGER_VERSION, activatedStr, s_hostip, got_ip_by, s_port, dbStr, DatabasePrefix, serverID, liveStr, halfStr, score_1, score_2, g_hLasts.Length, GetClientsCount(4), GetClientsCount(5));

    if (log)
    {
        File file = OpenFile(s_DumpFile, "a");
        if (file != null)
        {
            file.WriteLine(format);
            delete file;
        }
    }
    PrintToServer(format);
}
