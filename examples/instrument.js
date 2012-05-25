var Provider = require('..').Provider,
    Consumer = require('..').Consumer;

function MyClass1() {
    this.method = function() { return 'boom!'; };
}

function MyClass2() {}

MyClass2.prototype.method1 = function(a, b) {
    this.method2({a: a, b: b, c: a + b, deep:{w:{x:{y:{z:'unseen?'}}}}});
};

MyClass2.prototype.method2 = function(x) {
    // do something slow
    for (var i = 0; i < 1000000; i++) {
        Math.sin(i, 0.5);
    }
    return x.c;
};

var provider = new Provider({name: 'example'});
provider.start('instrum');

var obj1 = new MyClass1();
obj1.method = provider.instrument(obj1.method, {name: 'MyClass1.method', scope: obj1});

provider.instrument(MyClass2.prototype, {name: 'MyClass2'});

var consumer = new Consumer();
consumer.start('example.instrum.*', function(subject) {
  subject.subscribe(function(sample) {
    if (sample.probe !== '_probes')
        console.log(sample.probe, sample.args[0], sample.args[1]);
  });
});

setTimeout(function() {

    obj1.method('yeah!');

    var obj2 = new MyClass2();
    obj2.method1(1, 2);
    obj2.method1(3, 4);

    provider.stop();
    consumer.stop({wait: 1000, disconnect: true});
}, 1000);

/*

Try the following command in another terminal window and then run this example script again:

    notrace sample \
    -p example.instrum.* \
    -f "probe!='_probes'" \
    -m "((this.l==null)&&(this.l=0),(this.e=probe=='func_enter'),(this.e)&&(this.l++),{fn:Array(this.l).join('  ') + (this.e?'-> ':'<- ') + args[0]})" \
    -M "((! this.e)&&(this.l--),{fn:fn})" \
    -t 100000

*/
