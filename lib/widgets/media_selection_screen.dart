import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// A screen to display and select media files.
class MediaSelectionScreen extends StatefulWidget {
  final List<AssetEntity> mediaList;

  const MediaSelectionScreen({Key? key, required this.mediaList}) : super(key: key);

  @override
  _MediaSelectionScreenState createState() => _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends State<MediaSelectionScreen> {
  Set<AssetEntity> selectedMedia = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Media'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, selectedMedia.toList());
            },
            child: const Text(
              'Done',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: GridView.builder(
        itemCount: widget.mediaList.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
        itemBuilder: (context, index) {
          AssetEntity asset = widget.mediaList[index];
          return FutureBuilder<Widget>(
            future: _buildThumbnail(asset),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (selectedMedia.contains(asset)) {
                        selectedMedia.remove(asset);
                      } else {
                        selectedMedia.add(asset);
                      }
                    });
                  },
                  child: Stack(
                    children: [
                      snapshot.data!,
                      if (selectedMedia.contains(asset))
                        const Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                );
              } else {
                return Container(
                  color: Colors.grey[300],
                );
              }
            },
          );
        },
      ),
    );
  }

  Future<Widget> _buildThumbnail(AssetEntity asset) async {
    final thumbnailData = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
    if (thumbnailData != null) {
      return Image.memory(
        thumbnailData,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      return Container(color: Colors.grey);
    }
  }
}
