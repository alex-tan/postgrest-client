# Changelog

## 3.0.0

- Add support for Maybe JWT to enable anonymous users. @rapind
- Add ability to pass custom headers with requests. @rapind

## 2.1.1

- Add "Prefer" "return=representation" header to delete requests. This resolves an issue where defaultSelect was specified with customEndpoint and postgrest wouldn't accept select as a parameter.

## 2.1.0

- Add support for `cs` and `cd` operators.

## 2.0.1

- Change ilike and like parameters to not be quoted. (Otherwise it wouldn't work with 5.2.0) Previously it would look like `ilike."value*"` but now it's `ilike.value*`.

## 2.0.0

- Adjust BadStatus type to include body string. This will be useful if postgrest responses change over time or if an HTTP service proxies to postgrest for the success case but returns a custom error response for the failure case.

## 1.0.0

- Initial fork from alex-tan/postgrest-queries with new features to create HTTP requests.
