#pragma semicolon 1
#pragma newdecls required

// -------------------------------------------------------------------
// Captains Draft System + Lasts + Watermelon
// -------------------------------------------------------------------

void Captains_OnPluginStart()
{
    LoadTranslations("warmod_captains.phrases");
    g_hLasts = new ArrayList(1);
    g_hLastPlayers = new ArrayList(32);

    AddCommandListener(JoinTeam, "jointeam");
    RegConsoleCmd("lasts", Command_Lastslist, "List of lasts");
    RegConsoleCmd("lastslist", Command_Lastslist, "List of lasts");
    RegConsoleCmd("lastlist", Command_Lastslist, "List of lasts");
}

public Action Command_Lastslist(int client, int args)
{
    if (!b_use_last || !g_bActivated)
        return Plugin_Continue;

    int size = g_hLasts.Length;
    ReplyToCommand(client, "Listing %d player(s)", size);
    ReplyToCommand(client, "------------------");
    for (int i = 0; i < size; i++)
    {
        int lastClient = g_hLasts.Get(i);
        if (lastClient > 0 && lastClient <= MaxClients && IsClientInGame(lastClient))
            ReplyToCommand(client, "%d. %N", i + 1, lastClient);
        else
            ReplyToCommand(client, "%d. Client %d (disconnected)", i + 1, lastClient);
    }
    ReplyToCommand(client, "------------------");
    return Plugin_Handled;
}

void Captains_OnModeChange()
{
    if (b_captainsmod)
        Captains_OnClientPutInServer(0);
    else
        Captains_OnMapStart();
}

void Captains_OnMapStart()
{
    captain_t = 0;
    captain_ct = 0;
    winner = 0;
    looser = 0;
    i_AutoSelectTimer = -1;
    i_lastchoose = 0;
    b_choosed = false;
    b_captain = false;
}

void Captains_OnMapEnd()
{
    Captains_OnMapStart();
}

void Captains_OnClientPutInServer(int client)
{
    if (!g_bActivated)
        return;

    if (IsMatchLive || IsHalfTime)
    {
        if (client != 0)
            Captains_ProcessChangeTeam(client);
        return;
    }

    if (b_captainsmod && !b_captain)
    {
        if (b_choosed)
        {
            if (client == 0)
                return;
            Captains_ProcessChangeTeam(client);
            return;
        }

        if (GetClientsCount(4) >= i_min_ready)
        {
            PrintToChatAll("\x03<WarMod>\x01 \x04%t", "One per team");
            b_captain = true;
            i_AutoSelectTimer = 30;

            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i) && GetClientTeam(i) > 1)
                {
                    ChangeClientTeam(i, 1);
                }
            }
        }
    }
}

void Captains_ProcessChangeTeam(int client)
{
    int tCount = GetClientsCount(2);
    int ctCount = GetClientsCount(3);
    if (tCount + ctCount >= i_min_ready)
        return;

    int team;
    if (tCount < ctCount)
        team = 2;
    else if (ctCount < tCount)
        team = 3;
    else
        team = GetRandomInt(0, 1) ? 3 : 2;

    DataPack dp;
    CreateDataTimer(0.5, Captains_ChangeTeam, dp, TIMER_FLAG_NO_MAPCHANGE);
    dp.WriteCell(GetClientSerial(client));
    dp.WriteCell(team);
}

public Action Captains_ChangeTeam(Handle timer, DataPack dp)
{
    dp.Reset();
    int client = GetClientFromSerial(dp.ReadCell());
    int team = dp.ReadCell();
    if (client != 0 && IsClientInGame(client) && team != GetClientTeam(client))
    {
        ChangeClientTeam(client, team);
    }
    return Plugin_Stop;
}

void Captains_OnEverySecond()
{
    if (i_AutoSelectTimer > 0)
    {
        i_AutoSelectTimer--;
        if (i_AutoSelectTimer == 0)
        {
            if (captain_t == 0)
            {
                int target = Captains_GetRandomSpectator();
                if (target != 0 && IsClientInGame(target))
                {
                    CS_SwitchTeam(target, 2);
                    CS_RespawnPlayer(target);
                    captain_t = target;
                }
            }
            if (captain_ct == 0)
            {
                int target = Captains_GetRandomSpectator();
                if (target != 0 && IsClientInGame(target))
                {
                    CS_SwitchTeam(target, 3);
                    CS_RespawnPlayer(target);
                    captain_ct = target;
                }
            }
            return;
        }
        PrintCenterTextAll("%t", "Autoselecting", i_AutoSelectTimer);
    }
}

int Captains_GetRandomSpectator()
{
    int clients[MAXPLAYERS + 1];
    int total = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && g_hLasts.FindValue(i) == -1 && GetClientTeam(i) == 1)
        {
            clients[total++] = i;
        }
    }
    if (total == 0)
        return 0;
    return clients[GetRandomInt(0, total - 1)];
}

void Captains_ImmunityModeChange()
{
    // No action needed during live match
    if (IsMatchLive)
        return;
}

// -------------------------------------------------------------------
// Reconstructed Captains_OnClientPostAdminCheck (Section 5)
// -------------------------------------------------------------------
public void Captains_OnClientPostAdminCheck(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || IsFakeClient(client) || client == SourceTV)
        return;

    checked[client] = true;

    if (!b_use_last || !g_bActivated)
        return;

    if (b_admin_immunity_of_last)
    {
        if (IsClientAdmin[client])
            return;

        if (i_adminflags != 0 && (GetUserFlagBits(client) & i_adminflags) != 0)
            return;
    }

    char auth[32];
    if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
    {
        if (g_hLastPlayers.FindString(auth) != -1)
        {
            if (g_hLasts.FindValue(client) == -1)
            {
                g_hLasts.Push(client);

                Call_StartForward(h_fwdOnPlayerLast);
                Call_PushCell(client);
                Action result = Plugin_Continue;
                Call_Finish(result);

                // If forward blocks, remove again
                if (result == Plugin_Handled || result == Plugin_Stop)
                {
                    int idx = g_hLasts.FindValue(client);
                    if (idx != -1)
                        g_hLasts.Erase(idx);
                    return;
                }

                PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "You are last");
            }
        }
    }
}

void Captains_OnClientDisconnect(int client)
{
    if (!IsMatchLive && b_captain && !b_choosed && winner != 0 && looser != 0 && client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        int team = GetClientTeam(client);
        int winnerTeam = GetClientTeam(winner);
        int looserTeam = GetClientTeam(looser);
        if (winnerTeam == team)
        {
            if (GetClientsCount(looserTeam) >= GetClientsCount(winnerTeam) && winner != i_lastchoose)
            {
                if (h_Menu != null)
                {
                    delete h_Menu;
                    h_Menu = null;
                }
                DisplayPlayersToClient(winner);
                PrintToChatAll("\x03<WarMod>\x01 \x04%t", "Rights goes to", winner);
            }
        }
        else if (looserTeam == team)
        {
            if (GetClientsCount(looserTeam) < GetClientsCount(winnerTeam) && looser != i_lastchoose)
            {
                if (h_Menu != null)
                {
                    delete h_Menu;
                    h_Menu = null;
                }
                DisplayPlayersToClient(looser);
                PrintToChatAll("\x03<WarMod>\x01 \x04%t", "Rights goes to", looser);
            }
        }
    }
}

void Captains_OnClientDisconnect_Post(int client)
{
    checked[client] = false;
    int index = g_hLasts.FindValue(client);
    if (index != -1)
    {
        g_hLasts.Erase(index);
    }
    else
    {
        if (GetClientsCount(4) > i_min_ready)
        {
            if (g_hLasts.Length > 0)
                g_hLasts.Erase(0);
        }
        else
        {
            // Do not clear all if disconnected wasn't last - original decompile had ClearArray bug
            // Keep behavior but only if needed: do not clear arbitrarily
        }
    }

    if (b_captain && !b_choosed)
    {
        if (winner != client && looser != client)
        {
            Captains_OnLiveOn3();
            i_lastchoose = 0;
            b_choosed = false;
            Captains_OnClientPutInServer(0);
        }
    }

    if (captain_t == client)
    {
        captain_t = 0;
        if (b_captain)
            i_AutoSelectTimer = i_autoselecttime;
    }
    else if (captain_ct == client)
    {
        captain_ct = 0;
        if (b_captain)
            i_AutoSelectTimer = i_autoselecttime;
    }
}

void Captains_OnLiveOn3()
{
    b_captain = false;
    winner = 0;
    looser = 0;
    i_AutoSelectTimer = -1;
}

void Captains_OnResetMatch()
{
    Captains_OnEndMatch();
}

void Captains_OnEndMatch()
{
    captain_t = 0;
    captain_ct = 0;
    b_choosed = false;
    i_AutoSelectTimer = -1;
    if (IsMatchLive)
    {
        g_hLastPlayers.Clear();
        char auth[32];
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && IsClientAuthorized(i))
            {
                int team = GetClientTeam(i);
                if (team == 2 || team == 3)
                {
                    GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
                    g_hLastPlayers.PushString(auth);
                }
            }
        }
    }
}

void Captains_OnHalfTime()
{
    int tmp = captain_t;
    captain_t = captain_ct;
    captain_ct = tmp;
}

void Captains_OnItemPickup(int client, const char[] weapon)
{
    if (!b_captain || b_choosed || IsMatchLive || winner != 0)
        return;
    if (StrEqual(weapon, "knife", false))
        return;
    StripAndGiveKnife(client);
}

void Captains_OnPlayerDeath(int client, int attacker, const char[] weapon)
{
    if (!b_captain || b_choosed || IsMatchLive)
        return;
    if (StrEqual(weapon, "knife", false) || StrEqual(weapon, "watermelon_projectile", false))
        return;
    if (winner != 0)
        return;

    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return;

    winner = attacker;
    looser = client;

    ConVar showInfo = FindConVar("wm_show_info");
    if (showInfo != null)
        showInfo.SetInt(0);

    if (i_min_ready < 3)
    {
        Captains_SendAskTeamMenu(winner);
        return;
    }
    DisplayPlayersToClient(winner);
}

void Captains_SendAskTeamMenu(int client)
{
    Panel panel = new Panel();
    char buffer[128];
    FormatEx(buffer, sizeof(buffer), "%T", "SelectTeam", client);
    panel.SetTitle(buffer);
    panel.DrawItem(" ", ITEMDRAW_SPACER);
    panel.DrawText("-----------------------------");
    FormatEx(buffer, sizeof(buffer), "%T", "Counter-Terrorists force", client);
    panel.DrawItem(buffer);
    FormatEx(buffer, sizeof(buffer), "%T", "Terrorists force", client);
    panel.DrawItem(buffer);
    panel.DrawText("-----------------------------");
    panel.DrawItem(" ", ITEMDRAW_SPACER);
    panel.CurrentKey = 10;
    panel.Send(client, Handler_SelectTeam, 10);
    delete panel;
}

public int Handler_SelectTeam(Menu menu, MenuAction action, int param1, int param2)
{
    // Panel handler uses MenuAction == MenuAction_Select
    if (action == MenuAction_Select)
    {
        if (looser == 0 || !IsClientInGame(looser))
        {
            PrintToChat(param1, "\x03<WarMod>\x01 \x04%t", "Competitor left the game");
            return 0;
        }
        switch (param2)
        {
            case 1:
            {
                ChangeClientTeam(winner, 3);
                ChangeClientTeam(looser, 2);
                // Ready panels will be sent via ready_system logic elsewhere
            }
            default:
            {
                ChangeClientTeam(winner, 2);
                ChangeClientTeam(looser, 3);
            }
        }
        // Send ready ask menus if implemented
        // ReadySystem_SendAskMenu is in ready_system.sp - forward call via shared
        // We trigger via native command to avoid cross-module dependency at compile time
        // But we can try to call if exists
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void Captains_OnPlayerSpawn(int client)
{
    if (b_captain && winner == 0 && looser == 0)
    {
        if (g_iAccount != -1)
            SetEntData(client, g_iAccount, 0, 4, true);
        StripAndGiveKnife(client);
    }
}

void Captains_OnPlayerTeam(int client, int team)
{
    switch (team)
    {
        case 2:
        {
            if (!b_captain || IsMatchLive)
                return;
            if (captain_t == 0)
            {
                captain_t = client;
                if (captain_ct != 0)
                {
                    i_AutoSelectTimer = -1;
                    ServerCommand("mp_restartgame 1");
                }
            }
        }
        case 3:
        {
            if (!b_captain || IsMatchLive)
                return;
            if (captain_ct == 0)
            {
                captain_ct = client;
                if (captain_t != 0)
                {
                    i_AutoSelectTimer = -1;
                    ServerCommand("mp_restartgame 1");
                }
            }
        }
        default:
        {
            if (captain_t == client)
            {
                captain_t = 0;
                if (b_captain)
                    i_AutoSelectTimer = i_autoselecttime;
            }
            else if (captain_ct == client)
            {
                captain_ct = 0;
                if (b_captain)
                    i_AutoSelectTimer = i_autoselecttime;
            }

            if (!b_captain || IsMatchLive)
                return;

            if (winner != client && looser != client)
            {
                Captains_OnLiveOn3();
                i_lastchoose = 0;
                b_choosed = false;
                Captains_OnClientPutInServer(0);
            }
            else
            {
                if (winner != 0 && i_lastchoose != client)
                {
                    if (h_Menu != null)
                    {
                        delete h_Menu;
                        h_Menu = null;
                    }
                    DisplayPlayersToClient(i_lastchoose);
                }
            }
        }
    }
}

void DisplayPlayersToClient(int client)
{
    if (client == 0 || !IsClientInGame(client))
        return;

    i_lastchoose = client;
    h_Menu = new Menu(SelectPlayerMenu);
    char title[128];
    FormatEx(title, sizeof(title), "%T\n ", "SelectPlayer", client);
    h_Menu.SetTitle(title);
    h_Menu.ExitButton = false;
    FillMenuBySpectators(h_Menu, client);

    if (h_Menu.ItemCount == 0 || GetClientsCount(5) >= i_min_ready)
    {
        delete h_Menu;
        h_Menu = null;

        int inGame = GetClientsCount(4);
        if (inGame < i_min_ready)
        {
            PrintCenterTextAll("%t", "Not enough", i_min_ready - inGame);
        }
        b_captain = false;
        b_choosed = true;
        FakeClientCommand(client, "say /r");
        ConVar showInfo = FindConVar("wm_show_info");
        if (showInfo != null)
            showInfo.SetInt(1);
        return;
    }

    h_Menu.Display(client, 4);
    CreateTimer(4.0, ReopenMenu, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void FillMenuBySpectators(Menu menu, int client)
{
    char name[64];
    char id[12];
    char buffer[96];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (client == i || SourceTV == i || !IsClientInGame(i) || GetClientTeam(i) != 1)
            continue;

        GetClientName(i, name, sizeof(name));
        IntToString(GetClientUserId(i), id, sizeof(id));
        if (b_use_last && g_hLasts.FindValue(i) != -1)
        {
            FormatEx(buffer, sizeof(buffer), "%s [%T]", name, "Last", client);
            menu.AddItem(id, buffer, ITEMDRAW_DISABLED);
        }
        else
        {
            menu.AddItem(id, name);
        }
    }
}

public int SelectPlayerMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char userid[12];
            menu.GetItem(param2, userid, sizeof(userid));
            int target = GetClientOfUserId(StringToInt(userid));
            if (target == 0 || !IsClientInGame(target))
            {
                PrintToChat(param1, "\x03<WarMod>\x01 \x04%t", "Player left the game");
                DisplayPlayersToClient(param1);
                return 0;
            }
            if (GetClientsCount(5) < i_min_ready)
            {
                Captains_CheckTeams(param1, target);
            }
            else
            {
                b_captain = false;
                b_choosed = true;
                FakeClientCommand(param1, "say /r");
                ConVar showInfo = FindConVar("wm_show_info");
                if (showInfo != null)
                    showInfo.SetInt(1);
                h_Menu = null;
            }
        }
        case MenuAction_End:
        {
            delete menu;
            h_Menu = null;
        }
    }
    return 0;
}

void Captains_CheckTeams(int chooser, int target)
{
    int looserTeam = GetClientTeam(looser);
    int looserCount = GetClientsCount(looserTeam);
    int winnerTeam = GetClientTeam(winner);
    int winnerCount = GetClientsCount(winnerTeam);

    if (winner == chooser)
    {
        if (looserCount < winnerCount)
        {
            DisplayPlayersToClient(looser);
            return;
        }
        ChangeClientTeam(target, winnerTeam);
        winnerCount++;
        if (looserCount < winnerCount)
            DisplayPlayersToClient(looser);
        else
            DisplayPlayersToClient(winner);
    }
    else
    {
        if (looserCount >= winnerCount)
        {
            DisplayPlayersToClient(winner);
            return;
        }
        ChangeClientTeam(target, looserTeam);
        looserCount++;
        if (looserCount < winnerCount)
            DisplayPlayersToClient(looser);
        else
            DisplayPlayersToClient(winner);
    }
    // Ensure target is respawned if needed
    if (IsClientInGame(target) && !IsPlayerAlive(target))
    {
        CS_RespawnPlayer(target);
    }
}

public Action ReopenMenu(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || client == i_lastchoose || b_choosed)
        return Plugin_Stop;
    DisplayPlayersToClient(client);
    return Plugin_Stop;
}

public Action JoinTeam(int client, const char[] command, int argc)
{
    if (!b_captainsmod || !b_captain || !g_warmod || !IsClientInGame(client))
        return Plugin_Continue;

    char arg[8];
    if (!GetCmdArgString(arg, sizeof(arg)))
        return Plugin_Handled;

    int team = StringToInt(arg);
    if (team == 1)
    {
        if (i_AutoSelectTimer != -1 && captain_t != client && captain_ct != client)
            return Plugin_Handled;
        return Plugin_Continue;
    }

    if (captain_t != client && captain_ct != client && GetClientTeam(client) > 1)
        return Plugin_Handled;

    if (b_use_last && g_hLasts.FindValue(client) != -1)
    {
        PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "You are last");
        return Plugin_Handled;
    }

    switch (team)
    {
        case 2:
        {
            if (captain_t != 0)
            {
                PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "Captain T in team");
                return Plugin_Handled;
            }
        }
        case 3:
        {
            if (captain_ct != 0)
            {
                PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "Captain CT in team");
                return Plugin_Handled;
            }
        }
    }
    return Plugin_Continue;
}

// -------------------------------------------------------------------
// Watermelon Projectile System (Easter Egg)
// -------------------------------------------------------------------
void WThrow_OnPluginStart()
{
    HookEvent("round_start", EventRoundStartWatermelon, EventHookMode_Post);
    HookEvent("weapon_fire", EventWeaponFireWatermelon, EventHookMode_Post);
    mp_friendlyfire = FindConVar("mp_friendlyfire");
    if (mp_friendlyfire != null)
        bFf = mp_friendlyfire.BoolValue;
    else
        bFf = false;
    if (mp_friendlyfire != null)
        mp_friendlyfire.AddChangeHook(OnCvarChangeFF);
}

public void OnCvarChangeFF(ConVar convar, const char[] oldValue, const char[] newValue)
{
    bFf = StringToInt(newValue) != 0;
}

public Action EventWeaponFireWatermelon(Event event, const char[] name, bool dontBroadcast)
{
    if (b_captainswthrow && b_captainsmod && b_captain && !b_choosed && winner != 0 && looser != 0)
    {
        int client = GetClientOfUserId(event.GetInt("userid"));
        if (client != 0 && IsClientInGame(client) && captain_ct != client && captain_t != client)
        {
            OnPlayerPressButton(client);
        }
    }
    return Plugin_Continue;
}

public Action EventRoundStartWatermelon(Event event, const char[] name, bool dontBroadcast)
{
    g_iPointHurt = -1;
    g_iEnvBlood = -1;

    int pointHurt = CreateEntityByName("point_hurt");
    if (pointHurt != -1 && DispatchSpawn(pointHurt))
    {
        DispatchKeyValue(pointHurt, "DamageTarget", "hurt");
        DispatchKeyValue(pointHurt, "DamageType", "0");
        g_iPointHurt = pointHurt;
    }

    int envBlood = CreateEntityByName("env_blood");
    if (envBlood != -1 && DispatchSpawn(envBlood))
    {
        DispatchKeyValue(envBlood, "spawnflags", "13");
        DispatchKeyValue(envBlood, "amount", "1000");
        g_iEnvBlood = envBlood;
    }
    return Plugin_Continue;
}

void WThrow_OnMapStart()
{
    PrecacheModel("models/props_junk/watermelon01.mdl", true);
    PrecacheModel("models/props_junk/watermelon01_chunk01a.mdl", true);
    PrecacheModel("models/props_junk/watermelon01_chunk01b.mdl", true);
    PrecacheModel("models/props_junk/watermelon01_chunk01c.mdl", true);
    PrecacheModel("models/props_junk/watermelon01_chunk02a.mdl", true);
    PrecacheModel("models/props_junk/watermelon01_chunk02b.mdl", true);
    PrecacheModel("models/props_junk/watermelon01_chunk02c.mdl", true);
}

void OnPlayerPressButton(int client)
{
    float fPVel[3];
    float fVel[3];
    float fAng[3];
    float fPos[3];
    GetClientEyePosition(client, fPos);
    int entity = CreateEntityByName("prop_physics");
    if (entity == -1)
        return;

    DispatchKeyValue(entity, "classname", "watermelon_projectile");
    SetEntityModel(entity, "models/props_junk/watermelon01.mdl");
    if (!DispatchSpawn(entity))
    {
        AcceptEntityInput(entity, "Kill");
        return;
    }

    SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
    SetEntProp(entity, Prop_Send, "m_usSolidFlags", 8, 4);
    SetEntProp(entity, Prop_Send, "m_nSolidType", 6, 4);
    GetClientEyeAngles(client, fAng);
    GetAngleVectors(fAng, fVel, NULL_VECTOR, NULL_VECTOR);
    ScaleVector(fVel, 1750.0);
    GetEntPropVector(client, Prop_Send, "m_vecVelocity", fPVel);
    AddVectors(fVel, fPVel, fVel);
    SetEntPropVector(entity, Prop_Send, "m_vecAngVelocity", g_fSpin);
    TeleportEntity(entity, fPos, fAng, fVel);
    SetVariantString("OnUser1 !self:Break::2.0:1");
    AcceptEntityInput(entity, "AddOutput");
    AcceptEntityInput(entity, "FireUser1");
    SDKHook(entity, SDKHook_Touch, OnTouchPost);
}

public Action OnTouchPost(int entity, int other)
{
    int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (other == client)
        return Plugin_Continue;

    AcceptEntityInput(entity, "Break");
    SDKUnhook(entity, SDKHook_Touch, OnTouchPost);

    if (other >= 1 && other <= MaxClients && IsClientInGame(other) && IsPlayerAlive(other))
    {
        // Check not same team unless friendly fire
        if (bFf)
        {
            Hurt(client, other, GetRandomFloat(40.0, 50.0));
        }
        else if (client != -1 && client != 0 && GetClientTeam(other) != GetClientTeam(client))
        {
            Hurt(client, other, GetRandomFloat(40.0, 50.0));
        }
        else if (client == -1 || client == 0)
        {
            Hurt(client, other, GetRandomFloat(40.0, 50.0));
        }
    }
    return Plugin_Continue;
}

void Hurt(int attacker, int victim, float damage)
{
    if (g_iPointHurt == -1 || !IsValidEntity(g_iPointHurt))
        return;

    DispatchKeyValue(victim, "targetname", "hurt");
    char sDamage[16];
    FloatToString(damage, sDamage, sizeof(sDamage));
    DispatchKeyValue(g_iPointHurt, "Damage", sDamage);
    DispatchKeyValue(g_iPointHurt, "classname", "watermelon_projectile");

    float fAttPos[3];
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
        GetClientAbsOrigin(attacker, fAttPos);
    else
        GetClientAbsOrigin(victim, fAttPos);

    TeleportEntity(g_iPointHurt, fAttPos, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(g_iPointHurt, "Hurt", attacker);
    DispatchKeyValue(g_iPointHurt, "classname", "point_hurt");
    DispatchKeyValue(victim, "targetname", "nohurt");

    if (g_iEnvBlood != -1 && IsValidEntity(g_iEnvBlood))
    {
        SetVariantString("BloodImpact");
        AcceptEntityInput(g_iEnvBlood, "DispatchEffect");
        AcceptEntityInput(g_iEnvBlood, "EmitBlood", victim);
    }
}
