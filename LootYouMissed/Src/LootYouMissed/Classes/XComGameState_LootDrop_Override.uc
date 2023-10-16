class XComGameState_LootDrop_Override extends XComGameState_LootDrop
	config(LYMconfig);

struct UniqueItemNamed
{
	var name ItemName;
	var int ItemQty;
};

var config bool bShowExpiredLootList, bCameraPansToExpiredLoot;
var config string hexLootExpiredColor_Messages, hexLootExpiredColor_ItemName, hexLootExpiredColor_ItemQty;


//CHANGE THE EXPIRED LOOT VISUALISATION TO ALSO DISPLAY SIDE MESSAGE
//THIS UPDATES ON EACH PLAYER TURN BEGUN TO EITHER THIS OR TICKED
function BuildVisualizationForLootExpired(XComGameState VisualizeGameState)
{
	local VisualizationActionMetadata ActionMetadata, EmptyTrack;

	local XComGameStateHistory History;
	local XComGameState_LootDrop LootDropState, OldLootDropState;
	local XComGameStateContext VisualizeStateContext;

	local XComContentManager ContentManager;
	local XComPresentationLayer Presentation;

	local XComWorldData World;
	local TTile EffectLocationTile;

	local X2ItemTemplateManager ItemTemplateManager;
	local XComGameState_Item ItemState;
	local name ItemTemplateName;
	local XGParamTag kTag;
	
	local array<StateObjectReference> LootItemRefs;
	local StateObjectReference LootItemRef;	
	local array<UniqueItemNamed> UniqueItems;
	local UniqueItemNamed ItemNamed;
	local int Index;

	local EWidgetColor DisplayColour;
	local string Display, LootReport;
	local bool bIsPsi, bItemFound;

	local X2Action_CameraLookAt CameraLookAt;
	local X2Action_StartStopSound SoundAction;
	local X2Action_PlaySoundAndFlyOver SoundAndFlyOver;
	local X2Action_PlayEffect LootExpiredEffectAction;
	local X2Action_LootDropMarker LootDropMarker;
	local X2Action_Delay DelayAction;
	local X2Action_PlayWorldMessage MessageAction;

	//SETUP OUR CONTEXT AND REPEAT SHORTCUTS
	VisualizeStateContext = VisualizeGameState.GetContext();

	World = `XWORLD;
	ContentManager = `CONTENT;
	History = `XCOMHISTORY;
	Presentation = `PRES;

	kTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));
	ItemTemplateManager = class'X2ItemTemplateManager'.static.GetItemTemplateManager();

	//ADD VISUAL PLAYTRACKS FOR THIS LOOT DROP
	History.GetCurrentAndPreviousGameStatesForObjectID(ObjectID, ActionMetadata.StateObject_OldState, ActionMetadata.StateObject_NewState, eReturnType_Reference, VisualizeGameState.HistoryIndex);
	
	/* NEW STATE */ LootDropState = XComGameState_LootDrop(ActionMetadata.StateObject_NewState);
	/* OLD STATE */ OldLootDropState = XComGameState_LootDrop(ActionMetadata.StateObject_OldState);
	/* ITEM REFS */ LootItemRefs = OldLootDropState.GetAvailableLoot();
	/* PSI LOOT? */ bIsPsi = OldLootDropState.HasPsiLoot();

	//GET THE 3D WORLD ACTOR MESH
	ActionMetadata.VisualizeActor = LootDropState.GetVisualizer();

	//MAKE THE CAMERA PAN OVER TO THE LOCATION OF THE LOOT DROP
	if (default.bCameraPansToExpiredLoot)
	{
		//CREATE NEW CAMERA COMMAND
		CameraLookAt = X2Action_CameraLookAt(class'X2Action_CameraLookAt'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
		CameraLookAt.LookAtObject = ActionMetadata.StateObject_NewState;
		CameraLookAt.BlockUntilActorOnScreen = true;
		CameraLookAt.UseTether = false;
		CameraLookAt.DesiredCameraPriority = eCameraPriority_GameActions; // increased camera priority so it doesn't get stomped
		//CameraLookAt.LookAtDuration = Delay; //WE DO THIS BY ATTACHED DELAY ACTION, DEFAULT TIME OF 1.5 SECONDS
	}

	//GET THE ACTUAL LOOT POST MARKER OBJECT, TICK THE COUNTER TO (ZERO) AND HIDE THE LOOT POST OBJECT
	LootDropMarker = X2Action_LootDropMarker(class'X2Action_LootDropMarker'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
	LootDropMarker.LootDropObjectID = ObjectID;
	LootDropMarker.LootExpirationTurnsRemaining = LootDropState.LootExpirationTurnsRemaining;
	LootDropMarker.LootLocation = LootDropState.GetLootLocation();
	LootDropMarker.SetVisible = false;

	//CONFIGURE FLYOVER MESSSAGE DISPLAY STRING BASED ON TYPE OF LOOT
	Display = bIsPsi ? class'XLocalizedData'.default.PsiLootExpiredMsg : class'XLocalizedData'.default.LootExpiredMsg;
	DisplayColour = bIsPsi ? eColor_Purple : eColor_Bad;

	SoundAndFlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyOver'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
	SoundAndFlyOver.SetSoundAndFlyOverParameters(SoundCue'SoundFX.ElectricalSparkCue', Display, '', DisplayColour, , 0, false, eTeam_XCom);

	//CLEAR UP LOOT DROP MARKERPOST VISUAL BASED ON LOOT TYPE
	if(bIsPsi)
	{
		//STOP THE PSI LOOT EFFECTS AND WOOSHWOOSH SOUND
		SoundAction = X2Action_StartStopSound(class'X2Action_StartStopSound'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
		SoundAction.Sound = new class'SoundCue';
		SoundAction.Sound.AkEventOverride = AkEvent'XPACK_SoundCharacterFX.Stop_Templar_Channel_Loot_Loop';
		SoundAction.vWorldPosition = History.GetVisualizer(LootDropState.ObjectID).Location;
		SoundAction.iAssociatedGameStateObjectId = LootDropState.ObjectID;
		SoundAction.bStopPersistentSound = true;
		SoundAction.bIsPositional = true;
	}
	else
	{
		//NORMAL LOOT EVAPORATE
		EffectLocationTile = LootDropState.GetLootLocation();
		LootExpiredEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
		LootExpiredEffectAction.EffectLocation = World.GetPositionFromTileCoordinates(EffectLocationTile);
		LootExpiredEffectAction.EffectName = ContentManager.LootExpiredEffectPathName;
		LootExpiredEffectAction.bStopEffect = false;
	}
	
	//ACTUALLY DESTROY THE 3D LOOT POST
	class'X2Action_LootDestruction'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext);

	//MAKE THIS ENTIRE THING HAVE A PAUSED DELAY - ONLY DO THIS IF THE CAMERA MOVED TO GIVE TIME FOR CAMERA MOVEMENT
	if(default.bCameraPansToExpiredLoot)
	{
		DelayAction = X2Action_Delay(class'X2Action_Delay'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
		DelayAction.Duration = 1.5;
	}
	
	//ADD NEW VISUAL TRACK FOR EACH ITEM IN THE DROP
	foreach LootItemRefs(LootItemRef)
	{
		//NEW TRACK
		ActionMetadata = EmptyTrack;
		History.GetCurrentAndPreviousGameStatesForObjectID(LootItemRef.ObjectID, ActionMetadata.StateObject_OldState, ActionMetadata.StateObject_NewState, eReturnType_Reference, VisualizeGameState.HistoryIndex);
		ActionMetadata.VisualizeActor = History.GetVisualizer(LootItemRef.ObjectID);

		//WAIT UNTIL ACTION CALLS - THIS MAKES ALL LOOT OBJECTS EVAPORATE AT SAME TIME
		class'X2Action_WaitForAbilityEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext);

		//EVAPORATE LOOT 3D VISUAL
		LootExpiredEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeStateContext));
		LootExpiredEffectAction.EffectLocation = ActionMetadata.VisualizeActor.Location;
		LootExpiredEffectAction.EffectName = ContentManager.LootItemExpiredEffectPathName;
		LootExpiredEffectAction.bStopEffect = false;

		//ADD THIS ITEM TO THE REPORT LIST IF ENABLED
		if (default.bShowExpiredLootList)
		{
			bItemFound = false;
	
			ItemState = XComGameState_Item(History.GetGameStateForObjectID(LootItemRef.ObjectID));
			if (ItemState != none)
			{
				ItemTemplateName = ItemState.GetMyTemplateName();

				//CHECK IF WE ALREADY GOT THIS, ADD TO OUR ITEM COLLECTION OR INCREASE EXISTING QTY
				//THIS COULD CREATE REALLY BAD LAG IF THE LOOT ITEM LIST IS LIKE 30+ INDIVIDUAL ITEM TYPES
				//EG (20x ELERIUM DUST, 20x ELERIUM DUST) COUNTS AS 1 INDIVIDUAL ITEM TYPES
				//EG (20x DUST, 5x INERT MELD) WOULD BE 2 INDIVIDUAL ITEM TYPES ... 
				for (Index = 0 ; Index < UniqueItems.Length ; Index++)
				{
					if (UniqueItems[Index].ItemName == ItemTemplateName)
					{
						UniqueItems[Index].ItemQty++; 	//increase the matched array item quantity number by one
						bItemFound = true;				//we found this item type, no need to ADD it or continue looking
						break;
					}
				}

				//NOT AN ITEM TYPE WE HAVE PREVIOUSLY REGISTERED, ADD NEW ENTRY
				if(!bItemFound)
				{
					ItemNamed.ItemName = ItemTemplateName;
					ItemNamed.ItemQty = ItemState.Quantity; //set this starting quantity to the item state quantity as the state might be a merged quantity item
					UniqueItems.AddItem(ItemNamed);
				}
			}
		}
	}

	//CREATE A NEW WORLD MESSAGE SIDE BANNER
	if (default.bShowExpiredLootList)
	{
		MessageAction = X2Action_PlayWorldMessage(class'X2Action_PlayWorldMessage'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));

		//ADD A NEW MESSAGE LINE FOR EACH UNIQUE ITEM WITH QUANTITY
		for( Index = 0; Index < UniqueItems.Length; Index++ )
		{
			//kTag.IntValue0 = UniqueItems[Index].ItemQty; //having to do this manually so we can colour it as a string, we can't as an integer
			LootReport = Repl(Presentation.m_strAutoLoot, "<XGParam:IntValue0/>", ColorText(string(UniqueItems[Index].ItemQty), default.hexLootExpiredColor_ItemQty) ); 

			//check the item name string isn't already with colour tags from localisation, if not we can colour it here for us
			kTag.StrValue0 = ItemTemplateManager.FindItemTemplate(UniqueItems[Index].ItemName).GetItemFriendlyNameNoStats();
			if (InStr(kTag.StrValue0, "<font color='#") == INDEX_NONE)	
			{
				kTag.StrValue0 = ColorText( kTag.StrValue0 , default.hexLootExpiredColor_ItemName);
			}

			//finally we add our new constructed string to the outgoing message	...	...	...	(qty) <item name> dropped. [psi] loot expired
			MessageAction.AddWorldMessage(`XEXPAND.ExpandString(LootReport) @ ColorText(Display, default.hexLootExpiredColor_Messages) ); 
		}
	}
}

static function string ColorText( string strValue, string HexColor )
{
    return "<font color='#"$HexColor$"'>"$strValue$"</font>";
}