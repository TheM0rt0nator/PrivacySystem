# PrivacySystem

Privacy System

This system is designed to stop players from entering certain spaces at the same time (e.g. a toilet cubicle)

- To setup this system, you must first place the "PrivacySystem" folder in ReplicatedStorage.

- Next, you need to move the PrivacySystem_Server script into ServerScriptService.

- To setup a privacy zone, simply tag a part using CollectionService with 'Privacy_Zone', or your custom tag (editable in Config module), and resize / position it to fit the area you want to be a private zone.

- If you want to create the zones on game start, there is a custom function in the Server_Handler module which you can fill in on line 23.

Here is the Roblox model if you'd prefer to add it in that way:
https://create.roblox.com/store/asset/131848367657779/PrivacySystem?assetType=Model&externalSource=www