#pragma semicolon 1
#pragma newdecls required

// -------------------------------------------------------------------
// StripAndGiveKnife - removes all weapons and gives knife
// Spec compliant: iterates slots 0-4, removes, gives weapon_knife, sets account to 0
// -------------------------------------------------------------------
stock void StripAndGiveKnife(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    for (int slot = 0; slot < 5; slot++)
    {
        int weapon = -1;
        while ((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
        {
            RemovePlayerItem(client, weapon);
            AcceptEntityInput(weapon, "Kill");
        }
    }

    int knife = GivePlayerItem(client, "weapon_knife");
    if (knife != -1)
    {
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", knife);
        DataPack pack;
        CreateDataTimer(0.1, Timer_EquipKnife, pack, TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(GetClientSerial(client));
        pack.WriteCell(EntIndexToEntRef(knife));
    }

    if (g_iAccount != -1)
    {
        SetEntData(client, g_iAccount, 0, 4, true);
    }
}

public Action Timer_EquipKnife(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientFromSerial(pack.ReadCell());
    int knifeRef = pack.ReadCell();
    int knife = EntRefToEntIndex(knifeRef);
    if (client != 0 && IsClientInGame(client) && IsPlayerAlive(client) && knife != -1 && IsValidEntity(knife))
    {
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", knife);
        FakeClientCommand(client, "use weapon_knife");
    }
    return Plugin_Stop;
}

// -------------------------------------------------------------------
// Weapons offset helper - cached
// -------------------------------------------------------------------
stock int Client_GetWeaponsOffset(int client)
{
    static int offset = -1;
    if (offset == -1)
    {
        offset = FindDataMapInfo(client, "m_hMyWeapons");
    }
    return offset;
}

// -------------------------------------------------------------------
// GetWeaponAmmoData - extracts clip and reserve ammo
// -------------------------------------------------------------------
stock void GetWeaponAmmoData(int client, int weapon, int &primaryClip, int &secondaryClip, int &reserveAmmo)
{
    primaryClip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    secondaryClip = GetEntProp(weapon, Prop_Send, "m_iClip2");

    int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType >= 0 && ammoType < 32)
    {
        int ammoOffset = FindDataMapInfo(client, "m_iAmmo");
        if (ammoOffset != -1)
        {
            reserveAmmo = GetEntData(client, ammoOffset + (ammoType * 4), 4);
        }
        else
        {
            reserveAmmo = -1;
        }
    }
    else
    {
        reserveAmmo = -1;
    }
}

// -------------------------------------------------------------------
// SetWeaponAmmoData - restores clip and reserve ammo
// -------------------------------------------------------------------
stock void SetWeaponAmmoData(int client, int weapon, int primaryClip, int secondaryClip, int reserveAmmo)
{
    if (primaryClip != -1)
        SetEntProp(weapon, Prop_Send, "m_iClip1", primaryClip);
    if (secondaryClip != -1)
        SetEntProp(weapon, Prop_Send, "m_iClip2", secondaryClip);

    int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType >= 0 && ammoType < 32 && reserveAmmo != -1)
    {
        int ammoOffset = FindDataMapInfo(client, "m_iAmmo");
        if (ammoOffset != -1)
        {
            SetEntData(client, ammoOffset + (ammoType * 4), reserveAmmo, 4, true);
        }
    }
}

// -------------------------------------------------------------------
// Client wrapper helpers (legacy SMLib compatibility, modernized)
// -------------------------------------------------------------------
stock int Weapon_GetPrimaryAmmoType(int weapon)
{
    return GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
}

stock int Weapon_GetSecondaryAmmoType(int weapon)
{
    return GetEntProp(weapon, Prop_Send, "m_iSecondaryAmmoType");
}

stock int Weapon_GetPrimaryClip(int weapon)
{
    return GetEntProp(weapon, Prop_Send, "m_iClip1");
}

stock void Weapon_SetPrimaryClip(int weapon, int value)
{
    SetEntProp(weapon, Prop_Send, "m_iClip1", value);
}

stock int Weapon_GetSecondaryClip(int weapon)
{
    return GetEntProp(weapon, Prop_Send, "m_iClip2");
}

stock void Weapon_SetSecondaryClip(int weapon, int value)
{
    SetEntProp(weapon, Prop_Send, "m_iClip2", value);
}

stock void Client_GetWeaponPlayerAmmoEx(int client, int weapon, int &primaryAmmo, int &secondaryAmmo)
{
    int ammoOffset = FindDataMapInfo(client, "m_iAmmo");
    if (ammoOffset == -1)
        return;

    if (primaryAmmo != -1)
    {
        int offset = Weapon_GetPrimaryAmmoType(weapon) * 4 + ammoOffset;
        primaryAmmo = GetEntData(client, offset, 4);
    }
    if (secondaryAmmo != -1)
    {
        int offset = Weapon_GetSecondaryAmmoType(weapon) * 4 + ammoOffset;
        secondaryAmmo = GetEntData(client, offset, 4);
    }
}

stock void Client_SetWeaponPlayerAmmoEx(int client, int weapon, int primaryAmmo, int secondaryAmmo)
{
    int ammoOffset = FindDataMapInfo(client, "m_iAmmo");
    if (ammoOffset == -1)
        return;

    if (primaryAmmo != -1)
    {
        int offset = Weapon_GetPrimaryAmmoType(weapon) * 4 + ammoOffset;
        SetEntData(client, offset, primaryAmmo, 4, true);
    }
    if (secondaryAmmo != -1)
    {
        int offset = Weapon_GetSecondaryAmmoType(weapon) * 4 + ammoOffset;
        SetEntData(client, offset, secondaryAmmo, 4, true);
    }
}

stock int Client_GiveWeapon(int client, const char[] classname, bool switchTo)
{
    int weapon = CreateEntityByName(classname);
    if (weapon == -1)
        return -1;

    float origin[3];
    float angles[3];
    GetClientAbsOrigin(client, origin);
    GetClientAbsAngles(client, angles);
    DispatchSpawn(weapon);
    EquipPlayerWeapon(client, weapon);
    if (switchTo)
    {
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
    }
    return weapon;
}

stock int Client_GiveWeaponAndAmmo(int client, const char[] classname, bool switchTo, int primaryAmmo, int secondaryAmmo, int primaryClip, int secondaryClip)
{
    int weapon = Client_GiveWeapon(client, classname, switchTo);
    if (weapon == -1)
        return -1;

    if (primaryClip != -1)
        Weapon_SetPrimaryClip(weapon, primaryClip);
    if (secondaryClip != -1)
        Weapon_SetSecondaryClip(weapon, secondaryClip);

    Client_SetWeaponPlayerAmmoEx(client, weapon, primaryAmmo, secondaryAmmo);
    return weapon;
}

stock bool Weapon_IsValid(int weapon)
{
    if (!IsValidEdict(weapon))
        return false;
    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));
    return StrContains(classname, "weapon_", false) == 0;
}

// -------------------------------------------------------------------
// DealDamage via point_hurt
// -------------------------------------------------------------------
stock void DealDamage(int victim, float damage, int attacker = 0, const char[] weaponClass = "point_hurt")
{
    if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || !IsPlayerAlive(victim))
        return;

    int pointHurt = CreateEntityByName("point_hurt");
    if (pointHurt != -1)
    {
        DispatchKeyValue(victim, "targetname", "hurtme");
        DispatchKeyValue(pointHurt, "DamageTarget", "hurtme");

        char sDamage[16];
        FloatToString(damage, sDamage, sizeof(sDamage));
        DispatchKeyValue(pointHurt, "Damage", sDamage);
        DispatchKeyValue(pointHurt, "DamageType", "0");
        DispatchKeyValue(pointHurt, "classname", weaponClass);
        DispatchSpawn(pointHurt);

        if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
        {
            float fAttPos[3];
            GetClientAbsOrigin(attacker, fAttPos);
            TeleportEntity(pointHurt, fAttPos, NULL_VECTOR, NULL_VECTOR);
            AcceptEntityInput(pointHurt, "Hurt", attacker);
        }
        else
        {
            AcceptEntityInput(pointHurt, "Hurt", -1);
        }

        AcceptEntityInput(pointHurt, "Kill");
        DispatchKeyValue(victim, "targetname", "normal");
    }
}

// -------------------------------------------------------------------
// Utility helpers
// -------------------------------------------------------------------
stock int GetClientsCount(int filter)
{
    int num = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (SourceTV == i)
            continue;
        if (!IsClientInGame(i))
            continue;

        switch (filter)
        {
            case 0:
            {
                if (IsClientConnected(i))
                    num++;
            }
            case 1:
            {
                if (GetClientTeam(i) == 1)
                    num++;
            }
            case 2:
            {
                if (GetClientTeam(i) == 2)
                    num++;
            }
            case 3:
            {
                if (GetClientTeam(i) == 3)
                    num++;
            }
            case 4:
            {
                num++;
            }
            case 5:
            {
                int team = GetClientTeam(i);
                if (team == 2 || team == 3)
                    num++;
            }
            case 6:
            {
                if (IsPlayerAlive(i))
                    num++;
            }
        }
    }
    return num;
}

stock int Client_FindBySteamId(const char[] auth)
{
    char clientAuth[32];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientAuthorized(client))
            continue;
        GetClientAuthId(client, AuthId_Steam2, clientAuth, sizeof(clientAuth));
        if (StrEqual(auth, clientAuth, false))
            return client;
    }
    return -1;
}

stock void PrintBannedPlayer(const char[] name, const char[] auth, int length, const char[] reason)
{
    if (b_debug)
    {
        LogToFile(s_LogFile, "%s (%s) was banned for %d minutes. (reason: %s)", name, auth, length, reason);
    }
    if (b_banannounce)
    {
        PrintToChatAll("\x03<WarMod>\x01 \x04%t", "Banned", name, auth, length, reason);
    }
}

stock bool String_IsIP(const char[] str)
{
    int dots = 0;
    int numbers = 0;
    for (int i = 0; str[i] != '\0'; i++)
    {
        if (str[i] >= '0' && str[i] <= '9')
        {
            numbers++;
        }
        else if (str[i] == '.')
        {
            dots++;
            if (dots > 3)
                return false;
        }
        else if (str[i] == ':')
        {
            // allow port separator, ignore
        }
        else
        {
            return false;
        }
    }
    if (numbers == 0 || dots < 3)
        return false;
    return true;
}
