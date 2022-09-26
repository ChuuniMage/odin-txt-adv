package init;
import "core:slice"

VIEW_ENUM :: enum {
 	CHURCH,
	CLEARING,
	SKETE,
	CHAPEL,
	SHRINE,
}

NPC_ENUM :: enum {
 	ALEXEI,
}

PLAYER_ITEM :: enum {
 	AXE,
	LAZARUS_ICON,
	CHRIST_ICON,
	MARY_ICON,
	JBAPTIST_ICON,
}

vSTUMP_ItemState :: enum {
 	Default,
	AxewiseStuck,
}

AXE_ItemState :: enum {
	v_StumpwiseLodged,
	i_Default,
}

LAZARUS_ICON_ItemState :: enum {
	v_Default,
	v_Broken,
}

vSTUMP_ItemState_descriptions := [vSTUMP_ItemState] string {
	.Default = "Stump left behind from an old tree.Memories of childhood return.",
	.AxewiseStuck = "The stump is axewise stuck.",
}

AXE_ItemState_descriptions := [AXE_ItemState] string {
	.i_Default = "A well balanced axe. Much use.",
	.v_StumpwiseLodged = "The axe is stumpwise lodged.",
}

