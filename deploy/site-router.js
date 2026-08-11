// CloudFront Function (viewer-request) shared by both distributions.
//  1. Redirects www.theotroom.co.uk -> https://theotroom.co.uk (301). The test distribution never
//     sees a www host, so that branch is inert there — one function serves both.
//  2. Rewrites directory-style requests to their index.html (CloudFront only applies
//     default_root_object at the root, not for sub-paths), so /about/ -> /about/index.html.
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    if (host === 'www.theotroom.co.uk') {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: { location: { value: 'https://theotroom.co.uk' + request.uri } }
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
