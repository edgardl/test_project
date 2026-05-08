use strict;
use warnings;
use Test::More;
use JSON::MaybeXS;

our $app;

# Mock environment variables
BEGIN { $ENV{$_} = 'test' for qw(DB_NAME DB_USER DB_PASS DB_HOST ASANA_TOKEN) }

# Load script
require '/tmp/scripts/feedback_app.psgi';

subtest 'Security & Logic' => sub {
    # XSS Sanitization
    is(escape_html($_->[0]), $_->[1], "Escaping: $_->[2]") for (
        ['<script>', '&lt;script&gt;', 'tags'],
        ['"quote"', '&quot;quote&quot;', 'double quotes'],
        ["'quote'", '&#39;quote&#39;', 'single quotes'],
        [undef, '', 'null handling']
    );

    # Validation & CSRF stuff
    ok(is_valid_comment("Safe"), "Validates normal text");
    ok(!is_valid_comment($_), "Rejects invalid input") for ("", "   ", "A" x 1000);
    
    my $t1 = generate_csrf();
    is(length($t1), 64, "CSRF length correct");
    isnt($t1, generate_csrf(), "Tokens are unique");
};

subtest 'Web Routes' => sub {
    # Test cases
    my @cases = (
        ['GET',  '/',        200, qr/<form/],
        ['POST', '/submit',  403, qr//],      # Forbidden (No CSRF)
        ['GET',  '/missing', 404, qr//],
    );

    for (@cases) {
	my $res = $app->({ REQUEST_METHOD => $_->[0], PATH_INFO => $_->[1] });
        is($res->[0], $_->[2], "$_->[0] $_->[1] returns $_->[2]");
        like($res->[2][0], $_->[3], "Content matches") if $_->[3] ne qr//;
    }
};

subtest 'JSON' => sub {
    my $json = encode_json({ a => 1 });
    is(decode_json($json)->{a}, 1, "JSON round-trip ok");
};

done_testing();
