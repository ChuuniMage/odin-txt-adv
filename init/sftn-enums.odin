package init;

PALETTE :: enum {
    Church, Clearing, Skete,
}

ValidCommand :: enum  {
    Quit,
    Menu,
    Invalid,
    Save,
    Go,
    Look,
    Take,
    Place,
    Inventory,
    Talk,
    ListExits,
    Exit,
};

GameMode :: enum {
    _Default,
    _Menu,
    _Inventory,
    _Dialogue,
    _LookInside,
};

ViewType :: enum {
    Room, LookInside,
}