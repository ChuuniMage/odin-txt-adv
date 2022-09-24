package init;
import "core:slice"


add_scenery_items_hot :: proc (scenery_items:^SceneryItemData){
    add_scenery_item(scenery_items, .CHURCH, "CHURCH", "Dedicated to Saint Lazarus, this modest Church stands strong.");
    add_scenery_item(scenery_items, .CHURCH, "SHRINE", "The shrine stands tall on the hill, proud of its older brother.");
    add_scenery_item(scenery_items, .CHURCH, "TREE", "It is a bare tree, standing alone.");
    add_scenery_item(scenery_items, .CHURCH, "GATE", "Crudely drawn, and unfinished.");

    add_scenery_item(scenery_items, .CLEARING, "CLEARING", "A quiet clearing. A good place to find lazy trees.");
    add_scenery_item(scenery_items, .CLEARING, "TREES", "Loitering in the clearing, the trees don't have much to do." );

    add_scenery_item(scenery_items, .CLEARING, "STUMP", ..slice.enumerated_array(&vSTUMP_ItemState_view_descriptions));
    
    add_scenery_item(scenery_items, .SHRINE, "SHRINE", "Almost like a miniature church, the shrine keeps travellers hopes in a travel-sized temple.");
    add_scenery_item(scenery_items, .SHRINE, "CANDLE", "A sleeping soldier of metal and oil waits for its next call to duty.");

    add_scenery_item(scenery_items, .SKETE, "SKETE", "It is a sturdy, cozy skete.")

}

init_player_item_data_hot :: proc (s:^Item_State) {
    add_playerItem(&s.player_items, .CLEARING, .AXE, ..slice.enumerated_array(&AXE_ItemState_view_descriptions))
    lazarus_icon_description :="An icon St Lazarus being raised from the dead by Christ."
    add_playerItem(&s.player_items, .SHRINE, .LAZARUS_ICON, lazarus_icon_description)
}

add_synonyms_hot :: proc (ge:^GlobalEverything) {
    add_synonym(&ge.synonyms, "HATCHET", .AXE)
    add_synonym(&ge.synonyms, "ICON", .LAZARUS_ICON)
    add_synonym(&ge.synonyms, "LAZARUS", .LAZARUS_ICON)
}

init_npc_descriptions_hot :: proc (vd:^ViewData){  
    vd.npc_description[.ALEXEI] = "Alexei is stern, yet lively. His arms yearn to throw fools into deep, dark pits."
};

