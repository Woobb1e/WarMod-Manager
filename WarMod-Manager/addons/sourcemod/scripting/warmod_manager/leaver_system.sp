#pragma semicolon 1
#pragma newdecls required

void InitPlayerBan(const char[] name, const char[] authid, const char[] ip, const char[] reason, int length, bool activated, bool sourcebans, Database database, const char[] DBPrefix);

// -------------------------------------------------------------------
// Anti-Leaver & Spectator Replacement System
// -------------------------------------------------------------------

void LeaveSystem_OnPluginStart()
{
    LoadTranslations("warmod_leaver.phrases");
    g_hBanTrie = new StringMap();
    g_hBanArray = new ArrayList(32);
    g_hReplaceTrie = new StringMap();
}

void LeaveSystem_OnClientAuthorized(int client, const char[] auth)
{
    if (!g_bActivated || !IsMatchLive || !IsClientInGame(client))
        return;

    LeaveSystem_CheckClient(client, auth);
}

void LeaveSystem_OnClientPutInServer(int client)
{
    IsJoined[client] = false;
}

void LeaveSystem_OnClientPostAdminCheck(int client)
{
    CreateTimer(0.5, LeaveSystem_SendReplaceMenu, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action LeaveSystem_SendReplaceMenu(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;

    if (!IsMatchLive && !IsHalfTime)
        return Plugin_Stop;

    char auth[32];
    int targetSerial;
    if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) && g_hReplaceTrie.GetValue(auth, targetSerial))
    {
        int target = GetClientFromSerial(targetSerial);
        if (target != 0 && IsClientInGame(target))
        {
            LeaveSystem_SendAskMenu(client, target);
        }
    }
    return Plugin_Stop;
}

void LeaveSystem_OnMapEnd()
{
    LeaveSystem_OnEndMatch();
}

void LeaveSystem_OnEndMatch()
{
    char auth[32];
    Handle timer;
    for (int i = 0; i < g_hBanArray.Length; i++)
    {
        g_hBanArray.GetString(i, auth, sizeof(auth));
        if (g_hBanTrie.GetValue(auth, timer))
        {
            delete timer;
        }
    }
    g_hBanArray.Clear();
    g_hBanTrie.Clear();
    g_hReplaceTrie.Clear();
}

void LeaveSystem_OnPlayerTeam(int client, int team)
{
    switch (team)
    {
        case 2, 3:
        {
            IsJoined[client] = true;
            if (!g_bActivated || !IsMatchLive)
                return;
            LeaveSystem_CheckClient(client, "");
        }
        default:
        {
            IsJoined[client] = false;
        }
    }
}

void LeaveSystem_CheckClient(int client, const char[] authString)
{
    char auth[32];
    if (authString[0] == '\0')
    {
        GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    }
    else
    {
        strcopy(auth, sizeof(auth), authString);
    }

    Handle timer;
    if (g_hBanTrie.GetValue(auth, timer))
    {
        delete timer;
        g_hBanTrie.Remove(auth);
        int index = g_hBanArray.FindString(auth);
        if (index != -1)
            g_hBanArray.Erase(index);

        Call_StartForward(h_fwdOnPlayerReconnected);
        Call_PushCell(client);
        Call_Finish();

        if (b_debug)
            LogToFile(s_LogFile, "Player %N (%s) has reconnected and wouldn't be banned", client, auth);
    }
    else if (b_allowreplacements)
    {
        if (g_hBanArray.Length > 0)
        {
            char firstAuth[32];
            g_hBanArray.GetString(0, firstAuth, sizeof(firstAuth));
            g_hBanArray.Erase(0);
            if (g_hBanTrie.GetValue(firstAuth, timer))
            {
                delete timer;
                g_hBanTrie.Remove(firstAuth);
                Call_StartForward(h_fwdOnPlayerReplaced);
                Call_PushCell(client);
                Call_PushString(firstAuth);
                Call_Finish();

                g_hReplaceTrie.SetValue(firstAuth, GetClientSerial(client), true);
                if (b_debug)
                    LogToFile(s_LogFile, "Player %N replaced another player with steam %s", client, firstAuth);
            }
        }
    }
}

bool LeaveSystem_SayChat(int client, const char[] command)
{
    if (StrEqual(command, s_askcommands, false))
    {
        if (!IsMatchLive)
        {
            PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "Match not live");
            return true;
        }
        int team = GetClientTeam(client);
        if (team == 2 || team == 3)
        {
            if (!b_allowask)
            {
                PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "Feature disabled");
            }
            else
            {
                AttemptAsk(client);
            }
        }
        else
        {
            LeaveSystem_SendReplaceMenu(null, GetClientSerial(client));
        }
        return true;
    }
    return false;
}

void AttemptAsk(int client)
{
    Menu menu = new Menu(MenuReplacement);
    char title[128];
    FormatEx(title, sizeof(title), "%T\n ", "SelectSpectator", client);
    menu.SetTitle(title);
    menu.ExitButton = true;
    menu.ExitBackButton = false;

    char name[64];
    char id[12];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (client == i || SourceTV == i || !IsClientInGame(i))
            continue;
        int team = GetClientTeam(i);
        if (team == 2 || team == 3)
            continue;

        GetClientName(i, name, sizeof(name));
        IntToString(GetClientUserId(i), id, sizeof(id));
        if (iReplaceTarget[i] != 0)
        {
            Format(name, sizeof(name), "%s [%T]", name, "Requested", client);
            menu.AddItem(id, name, ITEMDRAW_DISABLED);
        }
        else
        {
            menu.AddItem(id, name);
        }
    }

    if (menu.ItemCount == 0)
    {
        delete menu;
        return;
    }
    menu.Display(client, 5);
}

public int MenuReplacement(Menu menu, MenuAction action, int param1, int param2)
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
                AttemptAsk(param1);
                return 0;
            }
            LeaveSystem_SendAskMenu(target, param1);
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void LeaveSystem_SendAskMenu(int client, int target)
{
    iReplaceTarget[client] = GetClientUserId(target);
    PrintToChat(target, "\x03<WarMod>\x01 \x04%t", "Asked", client);

    Panel panel = new Panel();
    char buffer[128];
    FormatEx(buffer, sizeof(buffer), "%T", "Wants you to replace him", target, client);
    panel.SetTitle(buffer);
    panel.DrawItem(" ", ITEMDRAW_SPACER);
    panel.DrawText("-----------------------------");
    FormatEx(buffer, sizeof(buffer), "%T", "Accept", client);
    panel.DrawItem(buffer);
    FormatEx(buffer, sizeof(buffer), "%T", "Decline", client);
    panel.DrawItem(buffer);
    panel.DrawText("-----------------------------");
    panel.DrawItem(" ", ITEMDRAW_SPACER);
    panel.CurrentKey = 10;
    panel.Send(client, Handler_ReplaceAskSelect, 10);
    delete panel;

    CreateTimer(10.0, TimerAsk, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public int Handler_ReplaceAskSelect(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        switch (param2)
        {
            case 1:
            {
                int requester = GetClientOfUserId(iReplaceTarget[param1]);
                iReplaceTarget[param1] = 0;
                if (requester == 0)
                    return 0;

                Action result = Plugin_Continue;
                Call_StartForward(h_fwdOnPlayerReplaceByCmd);
                Call_PushCell(param1);
                Call_PushCell(requester);
                Call_Finish(result);
                if (result == Plugin_Handled || result == Plugin_Stop)
                    return 0;

                ReplacePlayers(requester, param1);

                Call_StartForward(h_fwdOnPlayerReplacedByCmd);
                Call_PushCell(param1);
                Call_PushCell(requester);
                Call_Finish();
            }
            case 2:
            {
                int requester = GetClientOfUserId(iReplaceTarget[param1]);
                iReplaceTarget[param1] = 0;
                if (requester == 0)
                    return 0;
                PrintToChat(requester, "\x03<WarMod>\x01 \x04%t", "Declined your request", param1);
            }
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

public Action TimerAsk(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if (client != 0)
        iReplaceTarget[client] = 0;
    return Plugin_Stop;
}

// -------------------------------------------------------------------
// Exhaustive State Cloning Algorithm (Spec Module C #3)
// -------------------------------------------------------------------
void ReplacePlayers(int original, int target)
{
    if (original <= 0 || target <= 0 || !IsClientInGame(original) || !IsClientInGame(target))
        return;

    int team = GetClientTeam(original);
    int playerClass = GetEntProp(original, Prop_Send, "m_iClass");
    int frags = GetClientFrags(original);
    int deaths = GetClientDeaths(original);
    int money = -1;
    if (g_iAccount != -1)
        money = GetEntData(original, g_iAccount, 4);

    CS_SwitchTeam(target, team);
    IsJoined[target] = true;

    // Some CS:S versions have m_iClass via DataMap, handle both
    int classOffset = FindDataMapInfo(target, "m_iClass");
    if (classOffset != -1)
        SetEntData(target, classOffset, playerClass, 4, true);
    else
        SetEntProp(target, Prop_Send, "m_iClass", playerClass);

    SetEntProp(target, Prop_Send, "m_iFrags", frags);
    SetEntProp(target, Prop_Send, "m_iDeaths", deaths);
    if (g_iAccount != -1 && money != -1)
        SetEntData(target, g_iAccount, money, 4, true);

    if (IsPlayerAlive(original))
    {
        int health = GetClientHealth(original);
        int armor = GetEntProp(original, Prop_Send, "m_ArmorValue");
        bool hasHelmet = view_as<bool>(GetEntProp(original, Prop_Send, "m_bHasHelmet"));

        int activeWeapon = GetEntPropEnt(original, Prop_Send, "m_hActiveWeapon");
        char activeClassname[64];
        activeClassname[0] = '\0';
        if (activeWeapon != -1 && IsValidEntity(activeWeapon))
            GetEdictClassname(activeWeapon, activeClassname, sizeof(activeClassname));

        float vecPos[3];
        float vecAng[3];
        float vecVel[3];
        GetClientAbsOrigin(original, vecPos);
        GetClientEyeAngles(original, vecAng);
        GetEntPropVector(original, Prop_Data, "m_vecVelocity", vecVel);

        CS_RespawnPlayer(target);

        // Strip all weapons from target
        int offsetTarget = Client_GetWeaponsOffset(target);
        if (offsetTarget != -1)
        {
            for (int i = 0; i < 48; i++)
            {
                int w = GetEntDataEnt2(target, offsetTarget + i * 4);
                if (w != -1 && IsValidEntity(w))
                {
                    RemovePlayerItem(target, w);
                    AcceptEntityInput(w, "Kill");
                }
            }
        }

        // Clone inventory from original
        int offsetOrig = Client_GetWeaponsOffset(original);
        if (offsetOrig != -1)
        {
            for (int i = 0; i < 48; i++)
            {
                int weapon = GetEntDataEnt2(original, offsetOrig + i * 4);
                if (weapon == -1 || !IsValidEntity(weapon))
                    continue;

                char classname[64];
                if (!GetEdictClassname(weapon, classname, sizeof(classname)))
                    continue;
                if (StrContains(classname, "weapon_", false) != 0)
                    continue;

                int primaryClip = GetEntProp(weapon, Prop_Send, "m_iClip1");
                int secondaryClip = GetEntProp(weapon, Prop_Send, "m_iClip2");
                int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
                int reserveAmmo = -1;
                if (ammoType >= 0 && ammoType < 32)
                {
                    int ammoOffset = FindDataMapInfo(original, "m_iAmmo");
                    if (ammoOffset != -1)
                        reserveAmmo = GetEntData(original, ammoOffset + ammoType * 4, 4);
                }

                // Remove from original also to avoid duplication issues, but we kill later anyway?
                // Actually spec says: Remove all weapons from target (done), then Give cloned weapon
                // We need to preserve original weapons until cloning? We'll clone before removing from original
                // But original will be moved to spec anyway - we can just clone
                bool isActive = StrEqual(classname, activeClassname, false);

                int newWeapon = GivePlayerItem(target, classname);
                if (newWeapon != -1)
                {
                    if (primaryClip != -1)
                        SetEntProp(newWeapon, Prop_Send, "m_iClip1", primaryClip);
                    if (secondaryClip != -1)
                        SetEntProp(newWeapon, Prop_Send, "m_iClip2", secondaryClip);

                    if (ammoType >= 0 && ammoType < 32 && reserveAmmo != -1)
                    {
                        int ammoOffsetTarget = FindDataMapInfo(target, "m_iAmmo");
                        if (ammoOffsetTarget != -1)
                            SetEntData(target, ammoOffsetTarget + ammoType * 4, reserveAmmo, 4, true);
                    }

                    if (isActive)
                    {
                        SetEntPropEnt(target, Prop_Send, "m_hActiveWeapon", newWeapon);
                    }
                }
            }

            // Now strip original's weapons (already cloned)
            for (int i = 0; i < 48; i++)
            {
                int w = GetEntDataEnt2(original, offsetOrig + i * 4);
                if (w != -1 && IsValidEntity(w))
                {
                    RemovePlayerItem(original, w);
                    AcceptEntityInput(w, "Kill");
                }
            }
        }

        SetEntityHealth(target, health);
        SetEntProp(target, Prop_Send, "m_ArmorValue", armor);
        SetEntProp(target, Prop_Send, "m_bHasHelmet", hasHelmet);

        TeleportEntity(target, vecPos, vecAng, vecVel);
    }

    ChangeClientTeam(original, 1);
    SetEntProp(original, Prop_Send, "m_iFrags", 0);
    SetEntProp(original, Prop_Send, "m_iDeaths", 0);
    if (g_iAccount != -1)
        SetEntData(original, g_iAccount, 0, 4, true);
    IsJoined[original] = false;
}

void LeaveSystem_OnPlayerDisconnect(int client, const char[] reason)
{
    iReplaceTarget[client] = 0;

    if (!IsJoined[client] || !IsMatchLive)
        return;

    if (b_allowreplacements && b_autoreplacements)
    {
        int target = 0;
        char auth[32];
        if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
        {
            if (g_hLasts.Length > 0)
            {
                target = g_hLasts.Get(0);
                if (!IsClientInGame(target) || GetClientTeam(target) != 1)
                    target = 0;
            }
            if (target == 0)
            {
                for (int i = 1; i <= MaxClients; i++)
                {
                    if (IsClientInGame(i) && SourceTV != i && GetClientTeam(i) == 1)
                    {
                        target = i;
                        break;
                    }
                }
            }
            if (target != 0)
            {
                g_hReplaceTrie.SetValue(auth, GetClientSerial(target), true);
                ReplacePlayers(client, target);
                IsJoined[client] = false;
                return;
            }
        }
    }

    if (!b_bandisconnected || (b_ban_admins_immunity && IsClientAdmin[client]) || IsFakeClient(client))
        return;

    if (b_debug)
        LogToFile(s_LogFile, "Player %N left the match. (reason: %s)", client, reason);

    if (!StrEqual(reason, "Disconnect by user.", false) && !StrEqual(reason, "Disconnect by user", false))
        return;

    char sAuthID[32];
    char sName[64];
    char sIP[32];
    GetClientName(client, sName, sizeof(sName));
    GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID));
    GetClientIP(client, sIP, sizeof(sIP), true);

    int index = g_hBanArray.FindString(sAuthID);
    if (index != -1)
    {
        g_hBanArray.Erase(index);
        g_hBanTrie.Remove(sAuthID);
    }

    Action result = Plugin_Continue;
    Call_StartForward(h_fwdOnPlayerBan);
    Call_PushCell(client);
    Call_PushString(sName);
    Call_PushString(sAuthID);
    Call_PushString(sIP);
    Call_Finish(result);
    if (result == Plugin_Handled || result == Plugin_Stop)
        return;

    if (b_debug && g_bActivated)
        LogToFile(s_LogFile, "Player %N (%s | %s) is going to be banned in %.2f seconds", client, sAuthID, sIP, f_banin);

    ReplaceString(sName, sizeof(sName), "'", "", false);
    ReplaceString(sName, sizeof(sName), "%", "", false);
    ReplaceString(sName, sizeof(sName), "--", "", false);

    DataPack pack;
    Handle timer;
    if (IsSourcebansExists && h_Database != null)
    {
        timer = CreateDataTimer(f_banin, Sourcebans_BanPlayer, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        timer = CreateDataTimer(f_banin, BanPlayer, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
    pack.WriteString(sName);
    pack.WriteString(sIP);
    pack.WriteString(sAuthID);
    g_hBanArray.PushString(sAuthID);
    g_hBanTrie.SetValue(sAuthID, timer, false);

    if (!g_bActivated)
        TriggerTimer(timer);
}

public Action Sourcebans_BanPlayer(Handle timer, DataPack pack)
{
    char sName[64];
    char sAuthID[32];
    char sIP[32];
    pack.Reset();
    pack.ReadString(sName, sizeof(sName));
    pack.ReadString(sIP, sizeof(sIP));
    pack.ReadString(sAuthID, sizeof(sAuthID));

    g_hBanTrie.Remove(sAuthID);
    int index = g_hBanArray.FindString(sAuthID);
    if (index == -1)
        return Plugin_Stop;
    g_hBanArray.Erase(index);

    if (!IsMatchLive || GetClientsCount(5) >= i_min_ready)
        return Plugin_Stop;

    int target = Client_FindBySteamId(sAuthID);
    if (target > 0 && IsClientInGame(target))
    {
        if (GetClientTeam(target) == 1)
        {
            if (b_allowreplacements && g_bActivated)
                KickClient(target, "%t", "Left Match in Spec and not replaced");
            else
                KickClient(target, "%t", "Left Match in Spec");
        }
        return Plugin_Stop;
    }

    // Query timestamp then check bans
    if (h_Database == null)
    {
        // fallback to direct ban
        char reason[128];
        FormatEx(reason, sizeof(reason), "%T", "Leaving the match", LANG_SERVER);
        InitPlayerBan(sName, sAuthID, sIP, reason, i_bantime * 60, false, false, null, DatabasePrefix);
        return Plugin_Stop;
    }

    // Async get timestamp via query
    DataPack hPack = new DataPack();
    hPack.WriteString(sName);
    hPack.WriteString(sIP);
    hPack.WriteString(sAuthID);

    // Use DB timestamp query
    char query[1024];
    // We'll store time via GetTime() instead of DB UNIX_TIMESTAMP for simplicity, but also try DB query
    // For modern spec we use GetTime() and check SourceBans bans
    FormatEx(query, sizeof(query), "SELECT `created`, `length` FROM `%s_bans` WHERE `aid` = (SELECT `aid` FROM `%s_admins` WHERE `authid` = 'STEAM_ID_WARMOD') AND `authid` = '%s' ORDER BY `created` DESC", DatabasePrefix, DatabasePrefix, sAuthID);
    // Execute with current time in pack
    DataPack timePack = new DataPack();
    timePack.WriteCell(GetTime());
    timePack.WriteString(sName);
    timePack.WriteString(sIP);
    timePack.WriteString(sAuthID);
    h_Database.Query(CheckPlayerBan, query, timePack);

    // Also need original pack cleanup? We used timePack
    delete hPack;
    return Plugin_Stop;
}

public Action BanPlayer(Handle timer, DataPack pack)
{
    char sAuthID[32];
    char sName[64];
    char sIP[32];
    pack.Reset();
    pack.ReadString(sName, sizeof(sName));
    pack.ReadString(sIP, sizeof(sIP));
    pack.ReadString(sAuthID, sizeof(sAuthID));

    g_hBanTrie.Remove(sAuthID);
    int index = g_hBanArray.FindString(sAuthID);
    if (index == -1)
        return Plugin_Stop;
    g_hBanArray.Erase(index);

    if (!IsMatchLive || GetClientsCount(5) >= i_min_ready)
        return Plugin_Stop;

    int target = Client_FindBySteamId(sAuthID);
    if (target > 0 && IsClientInGame(target))
    {
        if (GetClientTeam(target) == 1)
        {
            if (b_allowreplacements && g_bActivated)
                KickClient(target, "%t", "Left Match in Spec and not replaced");
            else
                KickClient(target, "%t", "Left Match in Spec");
        }
        return Plugin_Stop;
    }

    char reason[128];
    FormatEx(reason, sizeof(reason), "%T", "Leaving the match", LANG_SERVER);
    InitPlayerBan(sName, sAuthID, sIP, reason, i_bantime, false, false, null, "sb");
    return Plugin_Stop;
}

public void CheckPlayerBan(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    if (results == null || error[0] != '\0')
    {
        LogError("Check Ban Query Failed: %s", error);
        if (pack != null)
            delete pack;
        return;
    }

    int banTime;
    int currentTime;
    int created = 0;
    int length = 0;
    int count = 0;
    char sAuthID[32];
    char sName[64];
    char sIP[32];
    char sReason[128];

    pack.Reset();
    currentTime = pack.ReadCell();
    pack.ReadString(sName, sizeof(sName));
    pack.ReadString(sIP, sizeof(sIP));
    pack.ReadString(sAuthID, sizeof(sAuthID));
    delete pack;

    int limit = i_resetbancount * 3600;
    int lastCreated = 0;
    int rowCount = 0;

    while (results.FetchRow())
    {
        int dummyCreated = results.FetchInt(0);
        int dummyLength = results.FetchInt(1);

        if (rowCount == 0)
        {
            created = dummyCreated;
            length = dummyLength;
            if (currentTime - dummyCreated <= limit)
                count++;
            if (b_debug)
                LogToFile(s_DumpFile, "%s (%s) - Unix_TimeStamp: %d, Count: %d, Created: %d, Length: %d", sName, sAuthID, currentTime, count, created, length);
            rowCount++;
            lastCreated = dummyCreated;
            continue;
        }
        else
        {
            if (lastCreated - dummyCreated <= limit)
                count++;
            if (b_debug)
                LogToFile(s_DumpFile, "%s (%s) - Unix_TimeStamp: %d, Count: %d, Created: %d, Length: %d", sName, sAuthID, currentTime, count, dummyCreated, dummyLength);
            lastCreated = dummyCreated;
            rowCount++;
        }
    }

    if (b_debug && rowCount == 0)
        LogToFile(s_DumpFile, "%s (%s) - Unix_TimeStamp: %d, Count: %d, Created: %d, Length: %d", sName, sAuthID, currentTime, count, created, length);

    switch (count)
    {
        case 0:
        {
            banTime = i_bantime * 60;
            FormatEx(sReason, sizeof(sReason), "%T", "Leaving the match", LANG_SERVER);
        }
        case 1:
        {
            banTime = i_bantimeextend * 60 + length;
            FormatEx(sReason, sizeof(sReason), "%T", "Leaving the match", LANG_SERVER);
        }
        default:
        {
            banTime = i_bantimeextend * 60 + length;
            FormatEx(sReason, sizeof(sReason), "%T", "Multiple match leaves", LANG_SERVER);
        }
    }

    bool activated = g_bActivated;
    InitPlayerBan(sName, sAuthID, sIP, sReason, banTime, activated, true, h_Database, DatabasePrefix);
}

// Forward declared in sourcebans_db.sp - provide weak reference
// InitPlayerBan will be defined in sourcebans_db.sp, declare as native forward here
// To avoid duplicate, we use shared function defined there. Declare extern.
