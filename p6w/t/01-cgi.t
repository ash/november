#!perl6

use Test;

plan 13;

use CGI;
ok(1);

my $cgi = CGI.new();
isa_ok( $cgi, 'CGI' );

# Don't know why I do this
$cgi.init();
isa_ok( $cgi, 'CGI', '...still' );

my @parse_params_test = (
    [ 'test=1',
      { :test<1> } ],
    [ 'test=2&params=2',
      { :test<2>, :params<2> },  ],
    [ 'test=3&params=3&words=first+second',
      { :test<3>, :params<3>, :words('first second') } ],
    [ 'test=4&params=3&words=first+%41+second',
      { :test<4>, :params<3>, :words('first A second') } ],
    [ 'test=5&params=3&words=first%0Asecond',
      { :test<5>, :params<3>, :words("first\nsecond") } ],
    );

for @parse_params_test -> $each {
    my $param = $each[0];
    my $result = $each[1];
    my %res = $cgi.parse_params( $param );
    is_deeply(%res, $result, 'Parse param: ' ~ $param);
}

my %start = {};
my @add_params_test = (
    [ :key1<val> , { :key1<val> } ],
    [ :key2<val> , { :key1<val>,      :key2<val> } ],
    [ :key1<val2>, { :key1<val val2>, :key2<val> } ],
    [ :key3<4>   , { :key1<val val2>, :key2<val>, :key3<4> } ],
    [ :key4<4.1> , { :key1<val val2>, :key2<val>, :key3<4>, :key4<4.1> } ],
);

for @add_params_test -> $each {
    my $key = $each[0].key;
    my $val = $each[0].value;
    my $result = $each[1];
    $cgi.add_param( %start, $key, $val);
    is_deeply( %start, $result, "Add kv: :$key<$val>" );
}

