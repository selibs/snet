package;

import s.URI;

class Tests {
	static function main() {
		assertUri("http://example.com", uri -> {
			assert(uri.proto == "http", "Expected normalized http scheme");
			assert(uri.host != null && uri.host.host == "example.com", "Expected example.com host");
			assert(uri.host.port == 80, "Expected default HTTP port");
		});

		assertUri("https://user:pass@example.com/path/to/resource?x=1#frag", uri -> {
			assert(uri.proto == "https", "Expected https scheme");
			assert(uri.isSecure, "Expected secure URI");
			assert(uri.user == "user", "Expected user info");
			assert(uri.pass == "pass", "Expected password info");
			assert(uri.query != null && uri.query["x"] == "1", "Expected query map with x=1");
			assert(uri.fragment == "frag", "Expected fragment without prefix");
		});

		assertUri("https://example.com/path?flag&x=1&empty=#frag", uri -> {
			assert(uri.query != null && uri.query.exists("flag"), "Expected flag query key");
			assert(uri.query["flag"] == null, "Expected null value for flag without equals");
			assert(uri.query["x"] == "1", "Expected x=1 query value");
			assert(uri.query["empty"] == "", "Expected empty string value for empty=");
		});

		assertUri("file:///C:/Temp/file.txt", uri -> {
			assert(uri.proto == "file", "Expected file scheme");
			assert(uri.hasAuthority == true, "Expected authority marker for file URI");
			assert(uri.host != null && uri.host.host == "", "Expected empty authority host");
			assert(uri.path == "/C:/Temp/file.txt", "Expected absolute file path");
		});

		assertUri("mailto:user@example.com", uri -> {
			assert(uri.proto == "mailto", "Expected mailto scheme");
			assert(uri.host == null, "Expected no authority host");
			assert(uri.path == "user@example.com", "Expected opaque path payload");
		});

		assertUri("urn:isbn:0451450523", uri -> {
			assert(uri.proto == "urn", "Expected urn scheme");
			assert(uri.path == "isbn:0451450523", "Expected URN payload");
		});

		assertUri("http://[::1]:8080/path", uri -> {
			assert(uri.host != null && uri.host.host == "[::1]", "Expected IPv6 host");
			assert(uri.host.port == 8080, "Expected explicit IPv6 port");
		});

		assertUri("//example.com/path", uri -> {
			assert(uri.proto == null, "Expected no scheme for protocol-relative URI");
			assert(uri.hasAuthority == true, "Expected protocol-relative authority");
			assert(uri.host != null && uri.host.host == "example.com", "Expected example.com host");
		});
	}

	static function assertUri(source:String, check:URI->Void) {
		var uri:URI = source;
		assert(uri != null, 'Failed to parse URI: $source');
		assert(uri.toString() == source, 'URI roundtrip mismatch for $source: ${uri.toString()}');
		check(uri);
	}

	static function assert(condition:Bool, message:String) {
		if (!condition)
			throw message;
	}
}
