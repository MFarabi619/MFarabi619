#include <unity.h>
#include <calculator.h>

Calculator calc;

void setUp(void){
  // set stuff up here
}

void tearDown(void){
  // clean stuff up here
}

void test_calculator_addition(void){
  TEST_ASSERT_EQUAL(32, calc.add(25, 7));
}

void test_calculator_subtraction(void){
  TEST_ASSERT_EQUAL(20, calc.subtract(23,3));
}

void test_calculator_multiplication(void){
  TEST_ASSERT_EQUAL(20, calc.multiply(4,5));
}

void test_calculator_division(void){
  TEST_ASSERT_EQUAL(32, calc.divide(96, 3));
}

void test_expensive_operation(void){
  TEST_IGNORE();
}

void RUN_UNITY_TESTS(){
  UNITY_BEGIN();
  RUN_TEST(test_calculator_addition);
  RUN_TEST(test_calculator_subtraction);
  RUN_TEST(test_calculator_multiplication);
  RUN_TEST(test_calculator_division);
  RUN_TEST(test_expensive_operation);
  UNITY_END();
}

#ifdef ARDUINO
#include <Arduino.h>

void setup(){
  // NOTE: wait for >2 secs if board doesn't support software reset via Serial.DTR/RTS
  delay(2000);

  pinMode(LED_BUILTIN, OUTPUT);
  RUN_UNITY_TESTS();
}

void loop(){
  digitalWrite(LED_BUILTIN, HIGH);
  delay(500);
  digitalWrite(LED_BUILTIN, LOW);
  delay(500);
}

#else

int main(int argc, char **argv){
  RUN_UNITY_TESTS();
  return 0;
}

#endif
