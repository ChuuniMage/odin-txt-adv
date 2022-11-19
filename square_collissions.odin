package main;


point_within_bounds :: proc (test_pt:[2]i32, ul:[2]i32, br:[2]i32) -> bool {
    return test_pt.x >= ul.x && test_pt.y >= ul.y && test_pt.x <= br.x && test_pt.y <= br.y
}