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
 	Default,
	StumpwiseLodged,
}

LAZARUS_ICON_ItemState :: enum {
	Default,
	Broken,
}

//TODO: Figure out priority between:
PLAYER_ITEM_view_descriptions := [PLAYER_ITEM] string {
	.AXE = "The axe is stumpwise lodged.",
	.LAZARUS_ICON = "An icon of St. Lazarus being raised from the dead by Christ.",
	.CHRIST_ICON = "An icon of Christ, the pantokrator.",
	.MARY_ICON = "An icon of the Virgin Mary, the Mother of God.",
	.JBAPTIST_ICON = "An icon of St. John the Baptist, holding his own severed head.",
}

PLAYER_ITEM_inv_descriptions := [PLAYER_ITEM] string {
	.AXE = "A well balanced axe. Much use.",
	.LAZARUS_ICON = "An icon of St. Lazarus being raised from the dead by Christ.",
	.CHRIST_ICON = "An icon of Christ, the pantokrator.",
	.MARY_ICON = "An icon of the Virgin Mary, the Mother of God.",
	.JBAPTIST_ICON = "An icon of St. John the Baptist, holding his own severed head.",
}

vSTUMP_ItemState_view_descriptions := [vSTUMP_ItemState] string {
	.Default = "Stump left behind from an old tree.Memories of childhood return.",
	.AxewiseStuck = "The stump is axewise stuck.",
}

AXE_ItemState_view_descriptions := [AXE_ItemState] string {
	.Default = "The axe is stumpwise lodged.",
	.StumpwiseLodged = "The axe is stumpwise lodged.",
}

