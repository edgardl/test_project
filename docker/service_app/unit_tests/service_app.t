use strict;
use warnings;
use Test::More;

# Load the logic from your script
# Note: We wrap this in a block to avoid issues with the builder execution
my $path = '/tmp/scripts/feedback_app.psgi';
require $path;

subtest 'HTML Escaping' => sub {
    is(escape_html('<script>'), '&lt;script&gt;', 'Left and right carats are escaped');
    is(escape_html('Edgar"s Project'), 'Edgar&quot;s Project', 'Double quotes are escaped');
    is(escape_html("Edgar's Project"), 'Edgar&#39;s Project', 'Single quotes are escaped');
    is(escape_html(undef), '', 'Undef returns an empty string');
};

subtest 'CSRF Generation' => sub {
    my $token1 = generate_csrf();
    my $token2 = generate_csrf();
    ok(length($token1) == 64, 'CSRF token is a 64-character SHA256 hex string');
    isnt($token1, $token2, 'Successive tokens are unique');
};

done_testing();
