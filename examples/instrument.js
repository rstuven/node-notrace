var Provider = require('..').Provider,
    Consumer = require('..').Consumer;

function MyClass1() {
    this.method = function() { return 'boom!'; };
    this.method2 = function(a,b,cb) {
        setTimeout(function(){
            cb(a+b, a*b);
        }, 123);
    };
}

function MyClass2() {}

MyClass2.prototype.method1 = function(a, b) {
    this.method2({a: a, b: b, c: a + b, deep:{w:{x:{y:{z:'unseen?'}}}}});
};

MyClass2.prototype.method2 = function(x) {
    // do something slow
    this.method3();
    this.method3();
    return x.c;
};

MyClass2.prototype.method3 = function() {
    for (var i = 0; i < 5000000; i++) {
        Math.sin(i, 0.5);
    }
}

MyClass2.prototype.method4 = function(a,b,cb) {
    setTimeout(function(){
        cb(a+b, a*b);
    }, 123);
};

var provider = new Provider({name: 'example'});
provider.start('instrum');

var obj1 = new MyClass1();
obj1.method = provider.instrument(obj1.method, {name: 'MyClass1.method', scope: obj1});
obj1.method2 = provider.instrument(obj1.method2, {name: 'MyClass1.method2', scope: obj1, callback: true});

provider.instrument(MyClass2.prototype, {name: 'MyClass2', callback: ['method4']});

var consumer = new Consumer();
consumer.start('example.instrum.*', function(subject) {
  subject.subscribe(function(sample) {
    if (sample.probe !== '_probes')
        console.log(sample.probe, sample.args[0], sample.args[1]);
        //console.log(sample);
  });
});

setTimeout(function() {

    obj1.method('yeah!');
    obj1.method2(2, 3, function(s, m) {
        console.log({s:s, m:m});
    });

    var obj2 = new MyClass2();
    obj2.method1(1, 2);
    obj2.method1(3, 4);
    obj2.method4(3, 4, function(s, m) {
        obj2.method1(2,3);
        console.log({s:s, m:m});
    });

    setTimeout(function(){
        provider.stop();
    }, 2000);
    consumer.stop({wait: 2500, disconnect: true});
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
