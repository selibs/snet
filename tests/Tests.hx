package;

import snet.http.Http;

class Tests {
	static function main() {
		run();
	}

	static function run() {
		trace(Http.request("http://example.com/"));
	}
}
