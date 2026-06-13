import os
import re

dir_path = "/Users/muhittincamdali/Desktop/Claude Projects/GitHub/FlutterNetworkKit/lib/src"

def add_imports():
    # 1. HttpMethod missing in request_batch.dart
    batch_path = os.path.join(dir_path, "batch/request_batch.dart")
    if os.path.exists(batch_path):
        with open(batch_path, 'r') as f: content = f.read()
        if "import '../client/base_client.dart';" not in content:
            content = "import '../client/base_client.dart';\n" + content
        # Also need ApiError.unknown -> ApiError.unknownError or similar
        # Let's check ApiError
        content = content.replace('ApiError.unknown', 'ApiError.requestFailed')
        with open(batch_path, 'w') as f: f.write(content)

    # 2. json.decode missing dart:convert
    json_path = os.path.join(dir_path, "utils/json_utils.dart")
    if os.path.exists(json_path):
        with open(json_path, 'r') as f: content = f.read()
        if "import 'dart:convert';" not in content:
            content = "import 'dart:convert';\n" + content
        with open(json_path, 'w') as f: f.write(content)

    # 3. response.dart toJson null safety
    resp_path = os.path.join(dir_path, "response/response.dart")
    if os.path.exists(resp_path):
        with open(resp_path, 'r') as f: content = f.read()
        # (data as dynamic).toJson() is the only way in Dart for generic toJson if not using a library
        content = content.replace('data.toJson()', '(data as dynamic).toJson()')
        with open(resp_path, 'w') as f: f.write(content)

add_imports()
print("Applied fixes to FlutterNetworkKit")
