part of jsm_deprecated;

import 'package:three_dart_jsm/three_dart_jsm/deprecated/index.dart';

class BoxGeometry extends Geometry {

  String type = "BoxGeometry";

	BoxGeometry( width, height, depth, widthSegments, heightSegments, depthSegments ) : super() {


		this.parameters = {
			"width": width,
			"height": height,
			"depth": depth,
			"widthSegments": widthSegments,
			"heightSegments": heightSegments,
			"depthSegments": depthSegments
		};

		this.fromBufferGeometry( 
      BoxBufferGeometry( 
        width: width, 
        height: height, 
        depth: depth, 
        widthSegments: widthSegments, 
        heightSegments: heightSegments, 
        depthSegments: depthSegments
      )
    );
		this.mergeVertices();

	}

}

