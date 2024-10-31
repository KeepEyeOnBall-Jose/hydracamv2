/// Represents a photo captured by a slave device, along with its metadata.
class CapturedPhoto {
  /// The file path where the photo is saved on the slave device.
  final String photoPath;

  /// The date and time when the photo was taken.
  final DateTime captureDate;

  /// The date and time when the photo was received by the master device.
  final DateTime receivedDate;

  /// An identifier for the slave device that captured the photo.
  final String slaveDeviceId;

  /// Constructor to initialize a CapturedPhoto with its path, capture date,
  /// received date, and the ID of the slave device.
  CapturedPhoto({
    required this.photoPath,
    required this.captureDate,
    required this.receivedDate,
    required this.slaveDeviceId,
  });
}