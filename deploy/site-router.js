// CloudFront Function (viewer-request) shared by both distributions.
//  1. Redirects the apex theotroom.co.uk -> https://www.theotroom.co.uk (301). The site is authored
//     with www as its canonical host (canonical/og tags, sitemap, robots all use www), so www is
//     primary and the bare apex redirects to it. The test distribution only ever sees
//     test.theotroom.co.uk, so this branch is inert there — one function serves both.
//  2. Rewrites directory-style requests to their index.html (CloudFront only applies
//     default_root_object at the root, not for sub-paths), so /about/ -> /about/index.html.
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    if (host === 'theotroom.co.uk') {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: { location: { value: 'https://www.theotroom.co.uk' + request.uri } }
        };
    }

    var uri = request.uri;
    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
    } else if (!uri.split('/').pop().includes('.')) {
        request.uri = uri + '/index.html';
    }

    return request;
}
