#pragma semicolon 1
#pragma newdecls required

void StopMatch();
#if !defined _mapchooser_included_
enum MapChange
{
    MapChange_MapEnd = 0,
    MapChange_MapStart,
    MapChange_RoundEnd
};
native bool CanMapChooserStartVote();
native void InitiateMapChooserVote(MapChange when, ArrayList array);
#endif

// -------------------------------------------------------------------
// Match Flow, Halftime & Ready System
// -------------------------------------------------------------------

void ReadySystem_OnPluginStart()
{
    LoadTranslations("warmod_ready.phrases");
    AddCommandListener(Command_JoinClass, "joinclass");
}

void ReadySystem_OnMapStart()
{
    // nothing
}

void ReadySystem_OnClientPutInServer()
{
    if (!g_warmod || g_h_min_ready == null)
        return;
    if (!IsMatchLive)
    {
        int inServer = GetClientsCount(4);
        if (inServer < i_min_ready)
            PrintCenterTextAll("%t", "Not enough", i_min_ready - inServer);
        ReadySystem_OnEverySecond();
    }
}

void ReadySystem_OnEverySecond()
{
    if (!g_warmod || g_h_min_ready == null)
        return;
    if (IsMatchLive)
        return;
    // Hint spam removed: PrintHintTextToAll("%t", "Not enough", ...) was spamming hint screen every second
    // if (GetClientsCount(4) < i_min_ready)
    //     PrintHintTextToAll("%t", "Not enough", i_min_ready - GetClientsCount(4));
}

void ReadySystem_OnClientDisconnect_Post(int client)
{
    IsReady[client] = false;
    if (i_overtimevote[client] != 0)
    {
        i_overtimevoters--;
        CheckOvertime();
    }
    i_overtimevote[client] = 0;
    if (IsMatchLive)
        ReadySystem_CheckTeams();
    ReadySystem_OnEverySecond();
}

void ReadySystem_OnLiveOn3()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        IsReady[i] = false;
        i_overtimevote[i] = 0;
    }
    i_overtimevoters = 0;
}

void ReadySystem_OnResetMatch()
{
    ReadySystem_OnEndMatch();
}

void ReadySystem_OnEndMatch()
{
    for (int i = 1; i <= MaxClients; i++)
        i_overtimevote[i] = 0;
    i_overtimevoters = 0;
}

void ReadySystem_OnPlayerTeam(int client, int team)
{
    if (team < 2)
        IsReady[client] = false;
}

// -------------------------------------------------------------------
// Chat Ready Hook
// -------------------------------------------------------------------
bool ReadySystem_SayChat(int client, const char[] command)
{
    if (StrEqual(command, "ready", false) || StrEqual(command, "rdy", false) || StrEqual(command, "r", false))
    {
        if (IsMatchLive)
            return true;
        if (!IsReady[client])
            IsReady[client] = true;

        // Mark bots as ready too
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && GetClientTeam(i) > 1 && IsFakeClient(i) && !IsReady[i])
                IsReady[i] = true;
        }
        ReadySystem_CheckAllPlayers();
        return true;
    }

    if (IsReady[client] && (StrEqual(command, "unready", false) || StrEqual(command, "notready", false) || StrEqual(command, "unrdy", false) || StrEqual(command, "notrdy", false) || StrEqual(command, "ur", false) || StrEqual(command, "nr", false)))
    {
        if (IsMatchLive)
            return true;
        IsReady[client] = false;
        return true;
    }
    return false;
}

void ReadySystem_CheckTeams()
{
    if (i_minplayers < 2)
        return;
    int inTeams = GetClientsCount(5);
    if (inTeams < i_minplayers)
    {
        StopMatch();
        if (b_debug)
            LogToFile(s_LogFile, "Minimum player reached! Min: %d, In teams: %d", i_minplayers, inTeams);
    }
}

void ReadySystem_CheckAllPlayers()
{
    int inTeams = GetClientsCount(5);
    if (inTeams >= i_min_ready)
    {
        if (!b_askmenu)
            return;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsReady[i] && IsClientInGame(i) && GetClientTeam(i) > 1 && !IsFakeClient(i))
                ReadySystem_SendAskMenu(i);
        }
    }
    else
    {
        if (IsMatchLive || IsHalfTime)
            PrintCenterTextAll("%t", "Not enough to team", i_min_ready - inTeams);
        int inGame = GetClientsCount(4);
        if (inGame < i_min_ready)
            PrintCenterTextAll("%t", "Not enough", i_min_ready - inGame);
    }
}

void ReadySystem_SendAskMenu(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    Panel panel = new Panel();
    char buffer[128];

    if (b_Overtime)
        FormatEx(buffer, sizeof(buffer), "%T", "Are you ready to overtime", client);
    else
        FormatEx(buffer, sizeof(buffer), "%T", "Are you ready to the match", client);

    panel.SetTitle(buffer);
    panel.DrawItem(" ", ITEMDRAW_SPACER);
    panel.DrawText("-----------------------------");
    FormatEx(buffer, sizeof(buffer), "%T", "Yes, I am always ready", client);
    panel.DrawItem(buffer);
    if (!b_Overtime)
    {
        FormatEx(buffer, sizeof(buffer), "%T", "No, I am not", client);
        panel.DrawItem(buffer);
    }
    else
    {
        FormatEx(buffer, sizeof(buffer), "%T", "Change map", client);
        panel.DrawItem(buffer);
    }
    panel.DrawText("-----------------------------");
    panel.DrawItem(" ", ITEMDRAW_SPACER);
    panel.CurrentKey = 10;
    panel.Send(client, Handler_Select, 10);
    delete panel;
}

public int Handler_Select(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        switch (param2)
        {
            case 1:
            {
                IsReady[param1] = true;
                FakeClientCommand(param1, "say /r");
                i_overtimevote[param1] = 1;
            }
            case 2:
            {
                PrintToChatAll("\x03<WarMod>\x01 %N \x04%t", param1, "Is not ready");
                i_overtimevote[param1] = 2;
            }
        }
        i_overtimevoters++;
        CheckOvertime();
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void CheckOvertime()
{
    if (b_Overtime && i_overtimevoters >= GetClientsCount(5))
    {
        int votes[2];
        for (int i = 1; i <= MaxClients; i++)
        {
            switch (i_overtimevote[i])
            {
                case 1: votes[0]++;
                case 2: votes[1]++;
            }
        }
        if (votes[0] < votes[1])
        {
            Mapchoose_OnEndMatch(true);
        }
        else
        {
            ServerCommand("fs");
        }
    }
}

// -------------------------------------------------------------------
// Halftime / Forcestart Automation
// -------------------------------------------------------------------
void Forcestart_OnPluginStart()
{
    // joinclass already hooked via ReadySystem_OnPluginStart alias, keep for compatibility
}

void ForceStart_OnResetMatch()
{
    if (h_AFKTimer != null)
    {
        delete h_AFKTimer;
        h_AFKTimer = null;
    }
}

void ForceStart_OnEndMatch()
{
    ResetReadies();
    if (h_AFKTimer != null)
    {
        delete h_AFKTimer;
        h_AFKTimer = null;
    }
}

void Forcestart_OnClientDisconnect_Post(int client)
{
    if (b_joined[client])
    {
        iReadyPlayers--;
        b_joined[client] = false;
    }
}

void ForceStart_OnLiveOn3()
{
    if (h_AFKTimer != null)
    {
        delete h_AFKTimer;
        h_AFKTimer = null;
    }
}

void Forcestart_OnHalfTime()
{
    ConVar autoSwap = FindConVar("wm_auto_swap");
    bool doSwap = false;
    if (autoSwap != null)
        doSwap = autoSwap.BoolValue;
    else if (wm_auto_swap != null)
        doSwap = wm_auto_swap.BoolValue;

    if (doSwap && i_forcestart > 0)
    {
        ResetReadies();
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && GetClientTeam(i) > 1 && IsFakeClient(i))
            {
                iReadyPlayers++;
                b_joined[i] = true;
            }
        }
        switch (i_forcestart)
        {
            case 3:
            {
                float delay = 3.0;
                if (wm_auto_swap_delay != null)
                    delay = wm_auto_swap_delay.FloatValue;
                CreateTimer(delay, AutoForce, _, TIMER_FLAG_NO_MAPCHANGE);
            }
            default:
            {
                CreateTimer(1.0, ForceStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
        }
        h_AFKTimer = CreateTimer(20.0, ForceStart_CheckForAfk, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Command_JoinClass(int client, const char[] command, int argc)
{
    if (!IsHalfTime || client == 0 || GetClientTeam(client) < 2 || b_joined[client])
        return Plugin_Continue;
    iReadyPlayers++;
    b_joined[client] = true;
    return Plugin_Continue;
}

public Action ForceStart_CheckForAfk(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!b_joined[i] && IsClientInGame(i))
        {
            int team = GetClientTeam(i);
            if (team == 2 || team == 3)
                KickClient(i, "You were AFK!");
        }
    }
    h_AFKTimer = null;
    return Plugin_Stop;
}

void Forcestart_OnPlayerTeam(int client, int team)
{
    if (b_joined[client] && team < 2)
    {
        b_joined[client] = false;
        iReadyPlayers--;
    }
}

public Action AutoForce(Handle timer)
{
    ServerCommand("fs");
    return Plugin_Stop;
}

public Action ForceStart(Handle timer)
{
    if (!IsHalfTime)
        return Plugin_Stop;

    int inTeams = GetClientsCount(5);
    if (inTeams < i_min_ready)
    {
        PrintCenterTextAll("%t", "Not enough to team", i_min_ready - inTeams);
    }
    else
    {
        switch (i_forcestart)
        {
            case 1:
            {
                if (iReadyPlayers >= inTeams)
                {
                    ServerCommand("fs");
                    IsHalfTime = false;
                    iReadyPlayers = 0;
                    ResetReadies();
                    return Plugin_Stop;
                }
            }
            default:
            {
                if (iReadyPlayers >= i_min_ready)
                {
                    ServerCommand("fs");
                    IsHalfTime = false;
                    iReadyPlayers = 0;
                    ResetReadies();
                    return Plugin_Stop;
                }
                else
                {
                    PrintCenterTextAll("%t", "Waiting for players", inTeams - iReadyPlayers);
                }
            }
        }
    }
    return Plugin_Continue;
}

void ResetReadies()
{
    iReadyPlayers = 0;
    for (int i = 1; i <= MaxClients; i++)
        b_joined[i] = false;
}

public Action Timer_RunOvertimeVote(Handle timer)
{
    ReadySystem_CheckAllPlayers();
    return Plugin_Stop;
}

// Mapchooser helper (stub if mapchooser not available)
void Mapchoose_OnEndMatch(bool override)
{
    if (b_initiatemapchoose || override)
    {
        ConVar showInfo = FindConVar("wm_show_info");
        if (showInfo != null)
            showInfo.SetInt(0);
        CreateTimer(1.0, StartMapChooserVote, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action StartMapChooserVote(Handle timer)
{
    if (LibraryExists("mapchooser") && CanMapChooserStartVote())
    {
        InitiateMapChooserVote(MapChange_MapEnd, null);
    }
    return Plugin_Stop;
}
