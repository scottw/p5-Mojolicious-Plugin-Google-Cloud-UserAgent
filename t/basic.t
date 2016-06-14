#!perl
use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

my $t = Test::Mojo->new;

plugin 'Google::Cloud::UserAgent' => {
    scopes        => ['https://www.googleapis.com/auth/pubsub'],
    gcp_auth_file => $ENV{GCP_AUTH_FILE},
    duration      => 5
};

my $time = time;

my $token1 = $t->app->jwt;
my $expires = $token1->issue_at + $token1->expires_in;
SKIP: {
    skip "GCP_AUTH_FILE or GCP_PROJECT not set; set to test", 2
      unless $ENV{GCP_AUTH_FILE} and $ENV{GCP_PROJECT};
    cmp_ok($expires, '>', $time, "token expires in the future");
    cmp_ok($expires, '<=', ($time + 5), "token expires within 5 seconds");
}

plugin 'Google::Cloud::UserAgent' => {
    scopes        => ['https://www.googleapis.com/auth/pubsub'],
    gcp_auth_file => $ENV{GCP_AUTH_FILE},
    duration      => 10,
};

get '/' => sub {
    my $c = shift;

    $c->render_later;

    $c->app->gcp_ua(
        GET => "https://pubsub.googleapis.com/v1/projects/$ENV{GCP_PROJECT}/topics",
        sub {
            my $tx = pop;
            $c->render(json => $tx->res->json, status => $tx->res->code);
        },
        sub {
            my ($tx, $c) = @_;
            $c->render(json => $tx->res->json, status => $tx->res->code);
        }
    );
};

SKIP: {
    skip "GCP_AUTH_FILE or GCP_PROJECT not set; set to test", 3
      unless $ENV{GCP_AUTH_FILE} and $ENV{GCP_PROJECT};

    $t->get_ok('/')->status_is(200)->json_has('/topics');
}

done_testing();
