import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BPage extends StatefulWidget {
  BPage({Key key}) : super(key: key);
  @override
  _BPageState createState() => _BPageState();
}

class _BPageState extends State<BPage> {
  MethodChannel _channel = MethodChannel('duia_texture_channel');//名称随意, 2端统一就好

  int daTextureId = -1; //系统返回的正常id会大于等于0, -1则可以认为 还未加载纹理

  @override
  void initState() {
    super.initState();

    newTexture();
  }

  @override
  void dispose() {
    super.dispose();
    if (daTextureId>=0){
      _channel.invokeMethod('dispose', {'textureId': daTextureId});

    }
  }

  void newTexture() async {
    daTextureId = await _channel.invokeMethod('create', {
      'img':'123.gif',//本地图片名
      'width': 200,
      'height': 300,
      'asGif':true,//是否是gif,也可以不这样处理, 平台端也可以自动判断
    });
    setState(() {
    });
  }

  Widget getTextureBody(BuildContext context) {
    return Container(
      // color: Colors.red,
      width: 300,
      height: 300,
      child: Texture(
        textureId: daTextureId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = daTextureId>=0 ? getTextureBody(context) : Text('loading...');

    return Scaffold(
      appBar: AppBar(
        title: Text("daex_texture"),
      ),
      body: Container(
        height: 500,
        width: 500,
        child: body,
      ),
    );
  }
}
