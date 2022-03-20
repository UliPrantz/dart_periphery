// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// https://github.com/vsergeev/c-periphery/blob/master/tests/test_gpio_sysfs.c

import 'package:dart_periphery/dart_periphery.dart';
import 'util.dart';
import 'dart:io';
import 'dart:isolate';

void test_arguments() {}

void test_open_config_close(int pinInput, int pinOutput) {
  // Open non-existent GPIO -- export should fail
  try {
    GPIO.sysfs(-1, GPIOdirection.GPIO_DIR_IN);
  } on GPIOexception catch (e) {
    if (e.errorCode != GPIOerrorCode.GPIO_ERROR_OPEN) {
      rethrow;
    }
  }

  var gpio = GPIO.sysfs(pinOutput, GPIOdirection.GPIO_DIR_IN);
  try {
    // Check properties
    passert(gpio.getLine() == gpio.line);
    passert(gpio.getGPIOfd() > 0);

    // Set direction out, check direction out, check value low
    gpio.setGPIOdirection(GPIOdirection.GPIO_DIR_OUT);
    passert(gpio.getGPIOdirection() == GPIOdirection.GPIO_DIR_OUT);
    passert(!gpio.read());

    // Set direction out, check direction out, check value low
    gpio.setGPIOdirection(GPIOdirection.GPIO_DIR_OUT_LOW);
    passert(gpio.getGPIOdirection() == GPIOdirection.GPIO_DIR_OUT);
    passert(!gpio.read());

    gpio.setGPIOdirection(GPIOdirection.GPIO_DIR_OUT_HIGH);
    passert(gpio.getGPIOdirection() == GPIOdirection.GPIO_DIR_OUT);
    passert(gpio.read());

    // Check GPIO inverted
    for (var b in [true, false]) {
      gpio.setGPIOinverted(b);
      passert(gpio.getGPIOinverted() == b);
    }

    gpio.setGPIOdirection(GPIOdirection.GPIO_DIR_IN);

    // Check GPIO edge
    for (var edge in GPIOedge.values) {
      print(edge);
      gpio.setGPIOedge(edge);
      passert(gpio.getGPIOedge() == edge);
    }
  } finally {
    gpio.dispose();
  }
}

void isolate(SendPort sendPort) async {
  print('start');
  var port = ReceivePort();
  // Notify any other isolates what port this isolate listens to.
  sendPort.send(port.sendPort);
  await for (var msg in port) {
    var replyTo = msg[0] as SendPort;
    var json = msg[1] as String;
    var gpio = GPIO.isolate(json);
    replyTo.send('start polling');
    var result = gpio.poll(1000);
    replyTo.send(result.index);
    port.close();
  }
  print('exit isolate');
}

Future<int> sync(ReceivePort response, GPIO gpio, bool value) async {
  var result = 0;
  await for (var msg in response) {
    if (msg is String) {
      print(msg);
      gpio.write(value);
    } else {
      result = msg as int;
      response.close();
    }
  }
  return result;
}

Future<SendPort> startIsolate() async {
  var receivePort = ReceivePort();
  await Isolate.spawn(isolate, receivePort.sendPort);
  var port = await receivePort.first as SendPort;
  return port;
}

Future<void> test_loopback(int pinInput, int pinOutput) async {
  var gpioIn = GPIO.sysfs(pinInput, GPIOdirection.GPIO_DIR_IN);
  var gpioOut = GPIO.sysfs(pinOutput, GPIOdirection.GPIO_DIR_OUT);
  try {
    // Drive out low, check in low
    gpioOut.write(false);
    passert(!gpioIn.read());

    // Drive out high, check in high
    gpioOut.write(true);
    passert(gpioIn.read());

    // Check poll falling 1 -> 0 interrupt
    gpioIn.setGPIOedge(GPIOedge.GPIO_EDGE_FALLING);

    var sendPort = await startIsolate();
    var response = ReceivePort();
    sendPort.send([response.sendPort, gpioIn.toJson()]);

    passert(await sync(response, gpioOut, false) == GPIOpolling.SUCCESS.index);
    passert(!gpioIn.read());

    // Check poll rising 0 -> 1 interrupt
    gpioIn.setGPIOedge(GPIOedge.GPIO_EDGE_RISING);

    sendPort = await startIsolate();
    response = ReceivePort();
    sendPort.send([response.sendPort, gpioIn.toJson()]);
    passert(await sync(response, gpioOut, true) == GPIOpolling.SUCCESS.index);
    passert(gpioIn.read());

    // Set both edge
    gpioIn.setGPIOedge(GPIOedge.GPIO_EDGE_BOTH);
    sendPort = await startIsolate();
    response = ReceivePort();
    sendPort.send([response.sendPort, gpioIn.toJson()]);
    passert(await sync(response, gpioOut, false) == GPIOpolling.SUCCESS.index);
    passert(!gpioIn.read());

    sendPort = await startIsolate();
    response = ReceivePort();
    sendPort.send([response.sendPort, gpioIn.toJson()]);
    passert(await sync(response, gpioOut, true) == GPIOpolling.SUCCESS.index);
    passert(gpioIn.read());

    // Check poll timeout
    passert(gpioIn.poll(1000) == GPIOpolling.TIMEOUT);

    // Check poll falling 1 -> 0 interrupt
    gpioOut.write(false);
    passert(GPIO.pollMultiple([gpioIn], 1000).hasEventOccured(gpioIn));
    passert(!gpioIn.read());

    // Check poll rising 0 -> 1 interrupt
    gpioOut.write(true);
    passert(GPIO.pollMultiple([gpioIn], 1000).hasEventOccured(gpioIn));
    passert(gpioIn.read());

    // Check poll timeout
    passert(!GPIO.pollMultiple([gpioIn], 1000).hasEventOccured(gpioIn));
  } finally {
    gpioIn.dispose();
    gpioOut.dispose();
    print('dispose...');
  }
}

void test_interactive(int pinOutput) {
  var gpioOut = GPIO.sysfs(pinOutput, GPIOdirection.GPIO_DIR_OUT);
  try {
    print('Starting interactive test. Get out your logic analyzer, buddy!');
    print('Press enter to continue...');
    pressKey();
    print('GPIO description: ${gpioOut.getGPIOinfo()}');
    print('GPIO description looks OK? y/n');
    pressKeyYes();

    //  Drive GPIO out low
    print('GPIO out is low? y/n');
    gpioOut.write(false);
    pressKeyYes();

    //  Drive GPIO out high
    print('GPIO out is high? y/n');
    gpioOut.write(true);
    pressKeyYes();

    //  Drive GPIO out low
    print('GPIO out is low? y/n');
    gpioOut.write(false);
    pressKeyYes();
  } finally {
    gpioOut.dispose();
  }
}

Future<void> main(List<String> argv) async {
  if (argv.length != 2) {
    print('Usage: dart gpio_test.dart <GPIO #1> <GPIO #2>');
    print('[1/4] Argument test: No requirements.');
    print('[2/4] Open/close test: GPIO #2 should be real.');
    print(
        '[3/4] Loopback test: GPIOs #1 and #2 should be connected with a wire.');
    print(
        '[4/4] Interactive test: GPIO #2 should be observed with a multimeter.\n');
    print('Hint: for Raspberry Pi 3,');
    print('Use GPIO 17 (header pin 11) and GPIO 27 (header pin 13),');
    print('connect a loopback between them, and run this test with:');
    print('    dart gpio_test.dart /dev/gpiochip0 17 27\n');
    exit(1);
  }

  var pinInput = int.parse(argv[0]);
  var pinOutput = int.parse(argv[1]);

  test_arguments();
  print('Arguments test passed.');
  test_open_config_close(pinInput, pinOutput);
  print('Open/close test passed.');
  await test_loopback(pinInput, pinOutput);
  print('Loopback test passed.');
  test_interactive(pinOutput);
  print('Interactive test passed.');
  print('All tests passed!\n');
}