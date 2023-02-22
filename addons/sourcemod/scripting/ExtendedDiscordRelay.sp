#include <sourcemod>
#include <SteamWorks>
#include <discordWebhookAPI>

#tryinclude <lilac>
#tryinclude <entWatch>
#tryinclude <KbRestrict>

#undef REQUIRE_PLUGIN
#tryinclude <sourcebanspp>
#tryinclude <sourcebanschecker>
#tryinclude <sourcecomms>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

enum MessageType {
    Message_Type_Eban 	= 0,
    Message_Type_Eunban = 1,
    Message_Type_Lilac 	= 2,
    Message_Type_Kban 	= 3,
    Message_Type_Kunban = 4,
    Message_Type_Ban 	= 5,
    Message_Type_Mute 	= 6,
    Message_Type_Unmute = 7,
    Message_Type_Gag 	= 8,
    Message_Type_Ungag 	= 9
}

enum struct Global_Stuffs {
	ConVar enable;
	ConVar webhook;
	ConVar website;
}

Global_Stuffs g_Lilac;
Global_Stuffs g_Eban;
Global_Stuffs g_Kban;
Global_Stuffs g_Sbpp;

/* GLOBAL VARIABLES */
ConVar g_cvSteamAPI;

char g_sClientAvatar[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name 		= "Extended-Discord-Relay",
	author 		= ".Rushaway, Dolly, koen",
	version 	= "2.3",
	description = "Send (Kban+Eban+Lilac+SBPP) notifications to discord",
	url 		= "https://nide.gg"
};

public void OnPluginStart()
{
	/* LILAC */
	g_Lilac.enable 	= CreateConVar("lilac_discord_enable", "1", "Toggle lilac notification system", _, true, 0.0, true, 1.0);
	g_Lilac.webhook = CreateConVar("lilac_discord", "", "The webhook URL of your Discord channel. (Lilac)", FCVAR_PROTECTED);
	
	/* Eban */
	g_Eban.enable 	= CreateConVar("eban_discord_enable", "1", "Toggle eban notification system", _, true, 0.0, true, 1.0);
	g_Eban.webhook 	= CreateConVar("eban_discord", "", "The webhook URL of your Discord channel. (Eban)", FCVAR_PROTECTED);
	g_Eban.website	= CreateConVar("eban_website", "https://ebans.nide.gg", "The Ebans Website for your server (that sends the user to ebans list page)", FCVAR_PROTECTED);
	
	/* Kban */
	g_Kban.enable 	= CreateConVar("kban_discord_enable", "1", "Toggle kban notification system", _, true, 0.0, true, 1.0);
	g_Kban.webhook 	= CreateConVar("kban_discord", "", "The webhook URL of your Discord channel. (Kban)", FCVAR_PROTECTED);
	g_Kban.website	= CreateConVar("kban_website", "https://kbans.nide.gg/index.php", "The Kbans Website for your server (that sends the user to bans list page)", FCVAR_PROTECTED);
	
	/* Sourcebans */
	g_Sbpp.enable 	= CreateConVar("sbpp_discord_enable", "1", "Toggle sourcebans notification system", _, true, 0.0, true, 1.0);
	g_Sbpp.webhook 	= CreateConVar("sbpp_discord", "", "The webhook URL of your Discord channel. (Sourcebans)", FCVAR_PROTECTED);
	g_Sbpp.website	= CreateConVar("sbpp_website", "https://bans.nide.gg/index.php", "Your sourcebans link", FCVAR_PROTECTED);
	
	g_cvSteamAPI = CreateConVar("lilac_steam_api", "", "API Web Steam. Get your own https://steamcommunity.com/dev/apikey", FCVAR_PROTECTED);

	AutoExecConfig(true, "Extended_Discord_Relay");
	
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i))
			continue;
			
		if(IsClientAuthorized(i)) 
			OnClientPostAdminCheck(i);
	}
}

public void OnClientPostAdminCheck(int client) {
	if(IsFakeClient(client) || IsClientSourceTV(client)) {
		return;
	}
	
	GetClientSteamAvatar(client);
}

public void OnClientDisconnect(int client) {
	g_sClientAvatar[client][0] = '\0';
}

stock void GetClientSteamAvatar(int client) {
	char steamID64[64];
	if(!GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64)))
		return;
	
	
	/* Steam API Key is set ? */
	char apiKey[PLATFORM_MAX_PATH];
	g_cvSteamAPI.GetString(apiKey, sizeof(apiKey));
	if (apiKey[0] == '\0') {
        LogError("[Extended-Discord-Relay] Invalid or no STEAM API Key specified in cfg/sourcemod/Extended_Discord_Relay.cfg");
        return;
    }
	
	Handle request = SteamWorks_CreateHTTPRequest(
        k_EHTTPMethodGET, "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?");
	
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "key", apiKey);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "format", "vdf");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "steamids", steamID64);
	SteamWorks_SetHTTPCallbacks(request, OnSummaryReceived);
	SteamWorks_SendHTTPRequest(request);
}

void OnSummaryReceived(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, DataPack pack) {
    if(!requestSuccessful || statusCode != k_EHTTPStatusCode200OK) {
        delete request;
        return;
    }

    int responseSize;
    SteamWorks_GetHTTPResponseBodySize(request, responseSize);

    char[] response = new char[responseSize];
    SteamWorks_GetHTTPResponseBodyData(request, response, responseSize);
    delete request;

    KeyValues kv = new KeyValues("response");
    kv.ImportFromString(response, "response");

    if(kv.JumpToKey("players") && kv.GotoFirstSubKey()) {
        char avatar[PLATFORM_MAX_PATH];
        kv.GetString("avatarfull", avatar, sizeof(avatar));
        
        char steamID64[64];
        kv.GetString("steamid", steamID64, sizeof(steamID64));
        int client = GetClientBySteamID64(steamID64);
        if(client == -1) {
        	delete kv;
        	return;
        }
        
        strcopy(g_sClientAvatar[client], sizeof(g_sClientAvatar[]), avatar);
    }

    delete kv;
}

int GetClientBySteamID64(const char[] steamID64) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i))
			continue;
		
		char steamID[64];
		if(!GetClientAuthId(i, AuthId_SteamID64, steamID, sizeof(steamID)))
			continue;
		
		if(StrEqual(steamID, steamID64, false))
			return i;
	}
	
	return -1;
}

#if defined _lilac_included
void SendLilacDiscordMessage(int client, char[] header, char[] details, char[] cheat, char[] line, char[] connect, char[] webhookURL) {
//----------------------------------------------------------------------------------------------------
/* Generate the Webhook */
//----------------------------------------------------------------------------------------------------
	Webhook webhook = new Webhook("");
	webhook.SetUsername("ZE Little Anti-Cheat");
	webhook.SetAvatarURL("https://avatars.githubusercontent.com/u/110772618?s=200&v=4");
	
	Embed Embed_1 = new Embed(header, details);
	Embed_1.SetTimeStampNow();
	Embed_1.SetColor(0xf79337);
	
	EmbedThumbnail Thumbnail = new EmbedThumbnail();
	Thumbnail.SetURL(g_sClientAvatar[client]);
	Embed_1.SetThumbnail(Thumbnail);
	delete Thumbnail;
	
	EmbedField Field_2 = new EmbedField("Reason", cheat, true);
	Embed_1.AddField(Field_2);

	EmbedField Infos = new EmbedField("Extra Infos", line, false);
	Embed_1.AddField(Infos);

	EmbedField Connect = new EmbedField("Quick Connect", connect, true);
	Embed_1.AddField(Connect);
	
	EmbedFooter Footer = new EmbedFooter("");
	Footer.SetIconURL("https://github.githubassets.com/images/icons/emoji/unicode/1f440.png");
	Embed_1.SetFooter(Footer);
	delete Footer;

	// Generate the Embed
	webhook.AddEmbed(Embed_1);
	
	// Push the message
	DataPack pack = new DataPack();
	pack.WriteCell(view_as<int>(webhook));
	pack.WriteString(webhookURL);
	
	webhook.Execute(webhookURL, OnWebHookExecuted, pack);
}

public void lilac_cheater_detected(int client, int cheat_type, char[] sLine)
{
	/* Plugin Enabled ? */
	if (!g_Lilac.enable.BoolValue)
		return;

	/* Webhook is set ? */
	char buffer[PLATFORM_MAX_PATH];
	g_Lilac.webhook.GetString(buffer, sizeof(buffer));
	if (buffer[0] == '\0') {
        LogError("[Extended-Discord-Relay] Invalid or no webhook specified for Lilac in cfg/sourcemod/Extended_Discord_Relay.cfg");
        return;
    }

	//----------------------------------------------------------------------------------------------------
	/* Generate all content we will need*/
	//----------------------------------------------------------------------------------------------------

	// Name + Formated Text
	char sName[64], sSuspicion[192];
	GetClientName(client, sName, sizeof(sName));
	FormatEx(sSuspicion, sizeof(sSuspicion), "Suspicion of cheating for `%s`", sName);

	// Client details
	char clientAuth[64], cIP[24], cDetails[240];
	GetClientIP(client, cIP, sizeof(cIP));
	if(!GetClientAuthId(client, AuthId_Steam2, clientAuth, sizeof(clientAuth)))
		strcopy(clientAuth, sizeof(clientAuth), "No SteamID");
		
	FormatEx(cDetails, sizeof(cDetails), "%s \nIP: %s", clientAuth, cIP);

	// Cheat Name
	char sCheat[64];
	GetCheatName(view_as<CHEATS>(cheat_type), sCheat, sizeof(sCheat));

	// Quick Connect
	int ip[4];
	if(!SteamWorks_GetPublicIP(ip)) {
		return;
	}
	
	ConVar cvar = FindConVar("hostport");
	if(!cvar) {
		return;
	}
	
	int port = cvar.IntValue;

	char connect[128];
	FormatEx(connect, sizeof(connect), "**steam://connect/%i.%i.%i.%i:%i**", ip[0], ip[1], ip[2], ip[3], port);

	/* Send Embed message */
	SendLilacDiscordMessage(client, sSuspicion, cDetails, sCheat, sLine, connect, buffer);
}
#endif
void SendDiscordMessage(MessageType type, int admin, int target, int length, const char[] reason, int bansNumber, int commsNumber, const char[] targetName = "", const char[] avatar = "") {
	char steamID[20];
	char steamID64[32];
	
	// Admin Information
	if(!GetClientAuthId(admin, AuthId_Steam2, steamID, sizeof(steamID))) { // should never happen
		return;
	}
	
	if(!GetClientAuthId(admin, AuthId_SteamID64, steamID64, sizeof(steamID64))) { // should never happen
		return;
	}
	
	bool invalidTarget = false;
	if(target > MaxClients || target < 1 || !IsClientInGame(target)) {
		invalidTarget = true;
	}

	char targetName2[32];
	if(!invalidTarget && !GetClientName(target, targetName2, sizeof(targetName2))) {
		return;
	}
	
	char title[32];
	GetTypeTitle(type, title, sizeof(title));
	
	char embedHeader[68+32];
	FormatEx(embedHeader, sizeof(embedHeader), "%s for `%s`", title, (invalidTarget) ? targetName : targetName2);
	
	int color = GetTypeColor(type); 
	
	Embed Embed1 = new Embed(embedHeader);
	Embed1.SetColor(color);
	Embed1.SetTitle(embedHeader);
	Embed1.SetTimeStampNow();
	
	EmbedThumbnail Thumbnail = new EmbedThumbnail();
	Thumbnail.SetURL(avatar);
	Embed1.SetThumbnail(Thumbnail);
	delete Thumbnail;
	
	char adminInfo[PLATFORM_MAX_PATH * 2];
	Format(adminInfo, sizeof(adminInfo), "`%N` ([%s](https://steamcommunity.com/profiles/%s))", admin, steamID, steamID64);
	EmbedField field1 = new EmbedField("Admin:", adminInfo, false);
	Embed1.AddField(field1);
	
	// Player Information
	if(!GetClientAuthId(target, AuthId_Steam2, steamID, sizeof(steamID))) {
		strcopy(steamID, sizeof(steamID), "No SteamID");
	}
	
	if(!GetClientAuthId(target, AuthId_SteamID64, steamID64, sizeof(steamID64))) {
		strcopy(steamID64, sizeof(steamID64), "No SteamID");
	}
	
	char playerInfo[PLATFORM_MAX_PATH * 2];
	if(StrContains(steamID, "STEAM_") != -1) {
		Format(playerInfo, sizeof(playerInfo), "`%N` ([%s](https://steamcommunity.com/profiles/%s))", target, steamID, steamID64);
	} else {
		Format(playerInfo, sizeof(playerInfo), "`%N` (No SteamID)", target);
	}
	
	EmbedField field2 = new EmbedField("Player:", playerInfo, false);
	Embed1.AddField(field2);
	
	// Reason
	EmbedField field3 = new EmbedField("Reason:", reason, false);
	Embed1.AddField(field3);
 
	char webhookURL[PLATFORM_MAX_PATH];
	if(!GetWebhook(type, webhookURL, sizeof(webhookURL))) {
	    LogError("[Extended-Discord-Relay] Invalid or no webhook specified in plugin config! for %s", title);
	    return;
	}
	
	/* Duration */
	if(type != Message_Type_Kunban && type != Message_Type_Eunban && type != Message_Type_Unmute && type != Message_Type_Ungag) {
		char timeBuffer[128];
		switch (length)
		{
		    case -1:
		    {
		        FormatEx(timeBuffer, sizeof(timeBuffer), "Temporary");
		    }
		    case 0:
		    {
		        FormatEx(timeBuffer, sizeof(timeBuffer), "Permanent");
		    }
		    default:
		    {
		        int ctime = GetTime();
		        int finaltime = ctime + (length * 60);
		        FormatEx(timeBuffer, sizeof(timeBuffer), "%d Minute%s \n(to <t:%d:f>)", length, length > 1 ? "s" : "", finaltime);
		    }
		}
		
		EmbedField fieldDuration = new EmbedField("Duration:", timeBuffer, true);
		Embed1.AddField(fieldDuration);
	}
	
	/* History Field */
	if(StrContains(steamID, "STEAM_") != -1) {
		char history[PLATFORM_MAX_PATH * 4];
		FormatTypeHistory(type, steamID, bansNumber, commsNumber, history, sizeof(history));
		
		EmbedField field5 = new EmbedField("History:", history, false);
		Embed1.AddField(field5);
	}
	
	Webhook hook = new Webhook("");
	hook.AddEmbed(Embed1);
	
	DataPack pack = new DataPack();
	pack.WriteCell(view_as<int>(hook));
	pack.WriteString(webhookURL);
	hook.Execute(webhookURL, OnWebHookExecuted, pack);
}

void GetTypeTitle(MessageType type, char[] title, int maxlen) {
	switch(type) {
		case Message_Type_Kban: {
			strcopy(title, maxlen, "Kban");
		}
		
		case Message_Type_Kunban: {
			strcopy(title, maxlen, "Kunban");
		}
		
		case Message_Type_Eban: {
			strcopy(title, maxlen, "Eban");
		}
		
		case Message_Type_Eunban: {
			strcopy(title, maxlen, "Eunban");
		}
		
		case Message_Type_Ban: {
			strcopy(title, maxlen, "Ban");
		}
		
		case Message_Type_Mute: {
			strcopy(title, maxlen, "Mute");
		}
		
		case Message_Type_Unmute: {
			strcopy(title, maxlen, "Unmute");
		}
		
		case Message_Type_Gag: {
			strcopy(title, maxlen, "Gag");
		}
		
		default: {
			strcopy(title, maxlen, "Ungag");
		}
	}
	
	FormatEx(title, maxlen, "%s Notification", title);
}

int GetTypeColor(MessageType type) {
	switch(type) {
		case Message_Type_Kban: {
			return 0xffff00;
		}
		
		case Message_Type_Kunban: {
			return 0x0000ff;
		}
		
		case Message_Type_Eban: {
			return 0xffffff;
		}
		
		case Message_Type_Eunban: {
			return 0x00ffff;
		}
		
		case Message_Type_Ban: {
			return 0xff0000;
		}
		
		case Message_Type_Mute: {
			return 0x00ff00;
		}
		
		case Message_Type_Unmute: {
			return 0xff0fA0;
		}
		
		case Message_Type_Gag: {
			return 0xffA200;
		}
		
		default: {
			return 0xffC2A0;
		}
	}
}

bool GetWebhook(MessageType type, char[] url, int maxlen) {
	if(type == Message_Type_Kban || type == Message_Type_Kunban) {
		g_Kban.webhook.GetString(url, maxlen);
	} else if(type == Message_Type_Eban || type == Message_Type_Eunban) {
		g_Eban.webhook.GetString(url, maxlen);
	} else {
		g_Sbpp.webhook.GetString(url, maxlen);
	}
	
	if(!url[0]) {
		return false;
	}
		
	return true;
}

void FormatTypeHistory(MessageType type, const char[] steamID, int bansNumber, int commsNumber, char[] history, int maxlen) {
	if(StrContains(steamID, "STEAM_") == -1) {
		return;
	}
	
	char webURL[PLATFORM_MAX_PATH];
	GetTypeWebsiteURL(type, webURL, sizeof(webURL));
	
	// View History link
	if(type == Message_Type_Kban || type == Message_Type_Kunban) {
		FormatEx(webURL, sizeof(webURL), "%s?all=true&s=%s&m=1", webURL, steamID);
		FormatEx(history, maxlen, "%d Kbans ([View History](%s))", bansNumber, webURL);
		return;
	} else if(type == Message_Type_Eban || type == Message_Type_Eunban) {
		FormatEx(webURL, sizeof(webURL), "%s?all=true&s=%s&m=1", webURL, steamID);
		FormatEx(history, maxlen, "%d Ebans ([View History](%s))", bansNumber, webURL);
		return;
	} else {
		char webURL1[PLATFORM_MAX_PATH];
		FormatEx(webURL1, sizeof(webURL1), "%s?p=banlist&searchText=%s&Submit", webURL, steamID);
		FormatEx(history, maxlen, "%d Bans ([View Bans](%s))", bansNumber, webURL1);

		ReplaceString(webURL1, sizeof(webURL1), "banlist", "commslist", false);
		FormatEx(history, maxlen, "%s\n%d comms ([View Comms](%s))", history, commsNumber, webURL1);
		return;
	}
}

void GetTypeWebsiteURL(MessageType type, char[] url, int maxlen) {
	if(type == Message_Type_Kban || type == Message_Type_Kunban) {
		g_Kban.website.GetString(url, maxlen);
		return;
	} else if(type == Message_Type_Eban || type == Message_Type_Eunban) {
		g_Eban.website.GetString(url, maxlen);
		return;
	} else {
		g_Sbpp.website.GetString(url, maxlen);
		return;
	}
}

#if defined _EntWatch_include
public void EntWatch_OnClientBanned(int admin, int length, int target, const char[] reason)
{
	if(!g_Eban.enable.BoolValue) {
		return;
	}
	
	if(admin < 1) {
		return;
	}
	
	int ebansNumber = EntWatch_GetClientEbansNumber(target);
	SendDiscordMessage(Message_Type_Eban, admin, target, length, reason, ebansNumber, 0, _, g_sClientAvatar[target]);
}

public void EntWatch_OnClientUnbanned(int admin, int target, const char[] reason)
{
    if (!g_Eban.enable.BoolValue)
    	return;
    
    if(admin < 1) {
		return;
	}
	
    int ebansNumber = EntWatch_GetClientEbansNumber(target);
    SendDiscordMessage(Message_Type_Eunban, admin, target, -1, reason, ebansNumber, 0, _, g_sClientAvatar[target]);
}
#endif

#if defined _KbRestrict_included_
public void KB_OnClientKbanned(int target, int admin, int length, const char[] reason, int kbansNumber)
{
	if(!g_Kban.enable.BoolValue) {
		return;
	}
	
	if(admin < 1) {
		return;
	}
	
	SendDiscordMessage(Message_Type_Kban, admin, target, length, reason, kbansNumber, 0, _, g_sClientAvatar[target]);
}

public void KB_OnClientKunbanned(int target, int admin, const char[] reason, int kbansNumber)
{
    if (!g_Kban.enable.BoolValue)
    	return;
    
    if(admin < 1) {
		return;
	}
	
    SendDiscordMessage(Message_Type_Kunban, admin, target, -1, reason, kbansNumber, 0, _, g_sClientAvatar[target]);  
}
#endif

#if defined _sourcebanspp_included
public void SBPP_OnBanPlayer(int admin, int target, int length, const char[] reason) {
	if(!g_Sbpp.enable.BoolValue) {
		return;
	}
	
	if(admin < 1) {
		return;
	}
	
	int bansNumber = 0;
	int commsNumber = 0;
	
	#if defined _sourcebanschecker_included
	bansNumber = SBPP_CheckerGetClientsBans(target);
	commsNumber = SBPP_CheckerGetClientsComms(target);
	bansNumber++;
	#endif
	
	SendDiscordMessage(Message_Type_Ban, admin, target, length, reason, bansNumber, commsNumber, _, g_sClientAvatar[target]);
}
#endif

#if defined _sourcecomms_included
public void SourceComms_OnBlockAdded(int admin, int target, int length, int commType, char[] reason) {
	if(!g_Sbpp.enable.BoolValue) {
		return;
	}
	
	if(admin < 1) {
		return;
	}
	
	MessageType type = Message_Type_Ban;
	switch(commType) {
		case TYPE_MUTE: {
			type = Message_Type_Mute;
		}
		
		case TYPE_UNMUTE: {
			type = Message_Type_Unmute;
		}
		
		case TYPE_GAG: {
			type = Message_Type_Gag;
		}
		
		case TYPE_UNGAG: {
			type = Message_Type_Ungag;
		}
	}
	
	if(type == Message_Type_Ban) {
		return;
	}
	
	int bansNumber = 0;
	int commsNumber = 0;
	
	#if defined _sourcebanschecker_included
	bansNumber = SBPP_CheckerGetClientsBans(target);
	commsNumber = SBPP_CheckerGetClientsComms(target);
	commsNumber++;
	#endif
	
	SendDiscordMessage(type, admin, target, length, reason, bansNumber, commsNumber, _, g_sClientAvatar[target]);
}
#endif
public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	pack.Reset();
	Webhook hook = view_as<Webhook>(pack.ReadCell());
	
	if (response.Status != HTTPStatus_OK) {
		PrintToServer("[Extended-Discord-Relay] An error has occured while sending the webhook. resending the webhook again.");
		
		char webhookURL[PLATFORM_MAX_PATH];
		pack.ReadString(webhookURL, sizeof(webhookURL));
		
		DataPack newPack;
		CreateDataTimer(0.5, ExecuteWebhook_Timer, newPack);
		newPack.WriteCell(view_as<int>(hook));
		newPack.WriteString(webhookURL);
		delete pack;
		return;
	}
	
	delete pack;
	delete hook;
}

Action ExecuteWebhook_Timer(Handle timer, DataPack pack) {
	pack.Reset();
	Webhook hook = view_as<Webhook>(pack.ReadCell());
	
	char webhookURL[PLATFORM_MAX_PATH];
	pack.ReadString(webhookURL, sizeof(webhookURL));
	
	DataPack newPack = new DataPack();
	newPack.WriteCell(view_as<int>(hook));
	newPack.WriteString(webhookURL);	
	hook.Execute(webhookURL, OnWebHookExecuted, newPack);
	return Plugin_Continue;
}
