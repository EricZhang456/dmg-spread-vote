#include <sourcemod>
#include <tf2>
#include <nativevotes>

bool g_bServerWaitingForPlayers, g_bNativeVotesLoaded;

ConVar g_cvDisableDamageSpread, g_cvPreRoundPushEnable, g_cvServerArena;

public Plugin myinfo = {
    name = "TF2 Damage Spread and Pre-Round Push Vote",
    author = "Eric Zhang",
    description = "Vote to toggle damage spread and pre-round push in TF2.",
    version = "1.0",
    url = "https://ericaftereric.top"
}

public void OnPluginStart() {
    g_cvDisableDamageSpread = FindConVar("tf_damage_disablespread");
    g_cvPreRoundPushEnable = FindConVar("tf_preround_push_from_damage_enable");
    g_cvServerArena = FindConVar("tf_gamemode_arena");

    RegServerCmd("sm_votespread", HandleVoteSpread, "Start a vote to toggle damage spread.");
    RegServerCmd("sm_votepush", HandleVotePush, "Start a vote to toggle pre-round push.");
}

public void OnMapStart() {
    ResetConVar(g_cvDisableDamageSpread);
    ResetConVar(g_cvPreRoundPushEnable);
}

public void OnServerEnterHibernation() {
    ResetConVar(g_cvDisableDamageSpread);
    ResetConVar(g_cvPreRoundPushEnable);
}

public void TF2_OnWaitingForPlayersStart() {
    if (!g_cvServerArena.BoolValue) {
        g_bServerWaitingForPlayers = true;
    }
}

public void TF2_OnWaitingForPlayersEnd() {
    if (!g_cvServerArena.BoolValue) {
        g_bServerWaitingForPlayers = false;
    }
}

public void OnLibraryAdded(const char[] name) {
    if (StrEqual(name, "nativevotes")) {
        g_bNativeVotesLoaded = true;
    }
}

public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, "nativevotes")) {
        g_bNativeVotesLoaded = false;
    }
}

public void OnAllPluginsLoaded() {
    if (LibraryExists("nativevotes")) {
        g_bNativeVotesLoaded = true;
    }
}