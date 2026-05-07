'use strict';

/**
 * CloudFront Lambda@Edge — Viewer Request
 *
 * Validates the X-Repo-Token header on every request to the
 * private APT repository. Requests without a valid token get 403.
 *
 * Deploy as a Lambda@Edge function associated with the
 * CloudFront distribution's viewer-request event.
 *
 * Environment:
 *   REPO_TOKEN is hardcoded below (Lambda@Edge doesn't support
 *   env vars — use a deployment script to inject the value).
 */

// ── REPLACE THIS with your actual fleet token ──
const EXPECTED_TOKEN = '9FPCQZ5Aaa1O9E-nNH14fmLst9gJ7mXiBNWjYThlA0W1uoHaRQ9RHxKud5OX5xzq';

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // Check for the auth token header
    const tokenHeader = headers['x-repo-token'];
    if (!tokenHeader || tokenHeader.length === 0 || tokenHeader[0].value !== EXPECTED_TOKEN) {
        return {
            status: '403',
            statusDescription: 'Forbidden',
            headers: {
                'content-type': [{ key: 'Content-Type', value: 'text/plain' }],
            },
            body: 'Access denied.\n',
        };
    }

    // Token valid — forward request to S3 origin
    // Remove the auth header so S3 doesn't see it
    delete request.headers['x-repo-token'];
    return request;
};
