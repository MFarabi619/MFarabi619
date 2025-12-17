fn calculate_length(s: &String) -> usize { // s is a reference to a String
  s.len()
} // Here, s goes out of scope. But because s does not have ownership of what it refers to, the String is not dropped.

// fn borrowing_without_returning(){
//   let s = String::from("hello");
//   change(&s);
// }

// fn change(some_string: &String){
//   some_string.push_str(", world");
// }

fn mutable_references(){
  let mut s = String::from("hello");
  {
    let r1 = &mut s;
  } // r1 goes out of scope here, so we can make a new reference with no problems.
  let r2 = &mut s;

  let r1 = &s; // no problem
  let r2 = &s; // no problem
  // let r3 = &mut s; // BIG PROBLEM

  // println!("{r1}, {r2}, and {r3}");
}

fn reference_scope(){
  let mut s = String::from("hello");
  let r1 = &s;     // no problem
  let r2 = &s;     // no problem
  println!("{r1} and {r2}");
  // Variables r1 and r2 will not be used after this point.

  let r3 = &mut s; // no problem
  println!("{r3}");
}

fn dangling_references(){
  // let reference_to_string = dangle();
  let reference_to_string = no_dangle();
}

// fn dangle() -> &String { // dangle returns a reference to a String
//   let s = String::from("hello"); // s is a new String
//   &s // we return a reference to the String, s
// } // Here, s goes out of scope and is dropped, so its memory goes away.
// // Danger!

fn no_dangle() -> String {
  let s = String::from("hello");
  s
}

fn main() {
  let s1 = String::from("hello");
  let len = calculate_length(&s1);
  println!("The length of '{s1}' is {len}.");

  // borrowing_without_returning();
  mutable_references();
  reference_scope();
}
