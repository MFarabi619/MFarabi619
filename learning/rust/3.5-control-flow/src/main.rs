fn if_expressions(){
  let number = 3;

  if number < 5 {
    println!("condition was true");
  } else {
    println!("condition was false");
  }

  let number = 7;

  if number < 5 {
    println!("condition was true");
  } else {
    println!("condition was false");
  }

  let number = 3;
  if number != 0 {
    println!("number was something other than zero");
  }
}

fn handling_multiple_conditions_with_else_if(){
  let number = 6;

  if number % 4 == 0 {
    println!("number is divisible by 4");
  } else if number % 3 == 0 {
    println!("number is divisible by 3");
  } else if number % 2 == 0 {
    println!("number is divisible by 2");
  } else {
    println!("number is not divisible by 4, 3, or 2");
  }
}

fn using_if_in_a_let_statement(){
  let condition = true;
  let number = if condition {5} else {6};

  println!("The value of number is: {number}");
}

fn repetition_with_loops(){
  loop {
    println!("again!");
  }
}

fn returning_values_from_loops(){
  let mut counter = 0;

  let result = loop {
    counter += 1;

    if counter == 10 {
      break counter * 2;
    }
  };

  println!("The result is {result}")
}

fn loop_labels_to_disambiguate_between_multiple_loops(){
  let mut count = 0;

  'counting_up: loop {
    println!("count = {count}");
    let mut remaining = 10;

    loop {
      println!("remaining = {remaining}");
      if remaining == 9 {
        break;
      }
      if count == 2 {
        break 'counting_up;
      }
      remaining -= 1;
    }
    count += 1;
  }
  println!("End count = {count}");
}

fn conditional_loops_with_while(){
  let mut number = 3;

  while number != 0 {
    println!("{number}!");
    number -= 1;
  }

  println!("LIFTOFF!!!");
}

fn looping_through_a_collection_with_for(){
  let a = [10, 20, 30, 40, 50];
  let mut index = 0;

  while index < 5 {
    println!("the value is: {}", a[index]);

    index += 1;
  }

  // more concise with for loop
  for element in a {
    println!("the value is: {element}");
  }
}

fn convert_temperature_between_fahrenheit_and_celcius(){
  loop {
    println!("Enter any number.");
    let mut number = String::new();

    std::io::stdin()
      .read_line(&mut number)
      .expect("Failed to read line");

    let number:u32 = match number
      .trim()
      .parse(){
        Ok(num) => num,
        Err(_) => continue
      };

    let celcius = (number - 32)/(9/5);
    let fahrenheit = (celcius*(9/5)) + 32;

    println!("{number}°F -> {celcius}°C");
    println!("{number}°C -> {fahrenheit}°F");
    break;
  }
}

fn generate_nth_fibonacci_number(){
  loop {
    println!("Enter any number for n.");
    let mut number = String::new();

    std::io::stdin()
      .read_line(&mut number)
      .expect("Failed to read line");

    let number:u32 = match number
      .trim()
      .parse(){
        Ok(num) => num,
        Err(_) => continue
      };

    match number.cmp(&1){
      std::cmp::Ordering::Less => println!("0"),
      std::cmp::Ordering::Equal => println!("1"),
      std::cmp::Ordering::Greater => {
        println!("Fn = Fn-1 + Fn+2 for n>1");
        println!("Example: 0,1,1,2,3,5,8,13,21");
      }
      break
    }
  }
}

fn main() {
  // if_expressions();
  // handling_multiple_conditions_with_else_if();
  // using_if_in_a_let_statement();
  // repetition_with_loops();
  // returning_values_from_loops();
  // loop_labels_to_disambiguate_between_multiple_loops();
  // conditional_loops_with_while();
  // looping_through_a_collection_with_for();
  convert_temperature_between_fahrenheit_and_celcius();
  generate_nth_fibonacci_number();
}
