// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appShellDeviceInfo => 'Información del dispositivo';

  @override
  String get appShellSettings => 'Configuración';

  @override
  String get appShellCameraSelection => 'Selección de cámara';

  @override
  String get appShellLocationInfo => 'Información de ubicación';

  @override
  String get appShellLogs => 'Registros';

  @override
  String get appShellUploaderInfo => 'Información de carga';

  @override
  String get appShellAppVersion => 'Versión de la app';

  @override
  String get appShellLogin => 'Iniciar sesión';

  @override
  String appVersionDialogContent(String version, String buildNumber) {
    return 'Versión: $version\nCompilación: $buildNumber';
  }

  @override
  String get dialogOk => 'OK';

  @override
  String get settingsPreferencesHeading => 'Preferencias';

  @override
  String get settingsLanguageTitle => 'Idioma';

  @override
  String get settingsLanguageDescription =>
      'Elige un idioma para la app o usa la configuración del dispositivo.';

  @override
  String get settingsLanguageSystemDefault => 'Predeterminado del sistema';

  @override
  String get settingsLanguageEnglish => 'Inglés';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageGerman => 'Alemán';

  @override
  String get settingsLanguagePolish => 'Polaco';

  @override
  String get settingsMasterShouldRecordTitle =>
      'El dispositivo maestro debe grabar';

  @override
  String get settingsCaptureHeading => 'Configuración de captura';

  @override
  String get settingsCameraLensTitle => 'Lente de cámara';

  @override
  String get settingsCameraLensDescription =>
      'Squash: usa ultra gran angular (0,5x) cuando el teléfono lo exponga.';

  @override
  String get settingsVideoProfileTitle => 'Perfil de vídeo';

  @override
  String get settingsVideoProfileDescription =>
      'Los perfiles son objetivos; el teléfono puede usar una alternativa si no los admite.';

  @override
  String settingsVideoTarget(String target) {
    return 'Objetivo: $target';
  }

  @override
  String get settingsDeleteLocalAfterUploadTitle =>
      'Borrar localmente tras subir';

  @override
  String get settingsAutoUploadMaterialsTitle =>
      'Subida automática de materiales';

  @override
  String get settingsStorageLocationTitle => 'Ubicación de almacenamiento';

  @override
  String get settingsStorageLocationDescription =>
      'HydraCam escribe actualmente las capturas en la carpeta de sesión de la app. La selección de tarjeta SD en Android necesita una estrategia de almacenamiento antes de poder habilitarse.';

  @override
  String get settingsInternalAppStorage => 'Almacenamiento interno de la app';

  @override
  String get settingsSdCardNotConfigured =>
      'Selección de tarjeta SD no configurada';

  @override
  String get settingsAutoplayVideoOnMasterTitle =>
      'Reproducir vídeo automáticamente en el maestro';

  @override
  String get settingsAutoplayVideoOnMasterDescription =>
      'Activa o desactiva la reproducción automática de vídeos después de grabarlos en el dispositivo maestro.';

  @override
  String get settingsAutoRecordModeTitle => 'Grabación automática';

  @override
  String get settingsAutoRecordModeDescription =>
      'Cuando está activado, los dispositivos sin operador pueden empezar a grabar automáticamente al unirse a una sesión activa.';

  @override
  String get settingsScreenAutoOffTitle => 'Autoapagado de pantalla';

  @override
  String get settingsScreenAutoOffDescription =>
      'Apaga la pantalla del esclavo durante la grabación para ahorrar batería. La pantalla se reactivará automáticamente o cuando la despiertes manualmente.';

  @override
  String get settingsTimerDurationTitle => 'Duración del temporizador';

  @override
  String get settingsTimerDurationDescription =>
      'Define el número de segundos para las cuentas atrás al grabar vídeos o tomar fotos.';

  @override
  String settingsTimerSeconds(int seconds) {
    return '$seconds segundos';
  }

  @override
  String settingsCurrentTimerDuration(int seconds) {
    return 'Duración actual del temporizador: $seconds segundos';
  }

  @override
  String get settingsFlashForVideoAnnouncementsTitle =>
      'Flash para avisos de vídeo';

  @override
  String get settingsFlashForVideoAnnouncementsDescription =>
      'Si está activado, el flash de la cámara parpadeará antes y después de grabar vídeo para indicar inicio/fin.';
}
