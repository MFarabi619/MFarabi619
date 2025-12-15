fn main() {
  println!("Hello, world!");

  another_function();
  print_labeled_measurement(5, 'h');
  an_expression();
  // statement_to_another_variable_wont_compile();
  statement_to_expression();

  let x = five();

  println!("The value of x is: {x}");

  let x = plus_one(5);

  println!("The value of x is: {x}");
}

fn another_function() {
  println!("Another function.");
}

fn print_labeled_measurement(value: i32, unit_label: char){
  println!("The measurement is: {value}{unit_label}")
}

fn an_expression(){
  let y = 6;
}

// fn statement_to_another_variable_wont_compile(){
//   let x = (let y =6);
// }

fn statement_to_expression(){
  let y = {
    let x = 3;
    x + 1
    // expressions don't include ending semicolons
    // adding a semicolor to the end of an expression turns it into a statement, which will not return a value
  };

  println!("The value of y is: {y}")
}

fn five() -> i32 {
  5
}

fn plus_one(x: i32) -> i32 {
  x + 1
}
