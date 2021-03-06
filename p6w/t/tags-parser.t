#!perl6

use Test;

plan 6;

use Wiki;

my @to_parse = (    
    [ 'foo',
      ['foo'] ],
    [ 'foo,bar',
      ['foo', 'bar'] ],
    [ 'foo, bar',
      ['foo', 'bar'] ],
    [ 'foo, bar ,her',
      ['foo', 'bar', 'her'] ],
    [ "foo\n",
      ['foo'] ],
    [ 'foo , bar    , her',
      ['foo', 'bar', 'her'] ],

);

for @to_parse -> $each {
    my $in = $each[0];
    my $result = $each[1];
    is_deeply( tags_parse($in), $result, 'Parse tags: ' ~ $in.perl);
}
