struct User {
    active: bool,
    username: String,
    email: String,
    sign_in_count: u64,
}

fn build_user(email: String, username: String) -> User {
    User {
        active: true,
        username,
        email,
        sign_in_count: 1,
    }
}

fn creating_different_types_with_tuple_structs() {
    struct Color(i32, i32, i32);
    struct Point(i32, i32, i32);

    let black = Color(0, 0, 0);
    let origin = Point(0, 0, 0);
}

fn defining_unit_like_structs() {
    struct AlwaysEqual;

    let subject = AlwaysEqual;
}

fn main() {
    let mut user1 = User {
        active: true,
        username: String::from("someusername123"),
        email: String::from("someone@example.com"),
        sign_in_count: 1,
    };

    user1.email = String::from("anotheremail@example.com");

    // let user2 = User {
    //   active: user1.active,
    //   username: user1.username,
    //   email: String::from("another@example.com"),
    //   sign_in_count: user1.sign_in_count,
    // };

    let user2 = User {
        email: String::from("another@example.com"),
        ..user1
    };

    creating_different_types_with_tuple_structs();
    defining_unit_like_structs();
}
