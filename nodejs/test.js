function * allIntegers ( ) {
    var i = 1;
    while (true) {
      yield i;
      i += 1;
    }
}

var ints = allIntegers();
console.log(ints.next().value); // 1
console.log(ints.next().value); // 2
console.log(ints.next().value); // 3
