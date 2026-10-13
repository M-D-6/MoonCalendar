import 'models.dart';

WeatherCondition conditionFromWmo(int code) {
  if (code == 0) return WeatherCondition.clear;
  if (code == 1) return WeatherCondition.clear; // mainly clear
  if (code == 2) return WeatherCondition.partlyCloudy;
  if (code == 3) return WeatherCondition.cloudy;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 51 && code <= 57) return WeatherCondition.drizzle;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return WeatherCondition.rain;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return WeatherCondition.snow;
  if (code == 95 || code == 96 || code == 99) return WeatherCondition.thunderstorm;
  return WeatherCondition.cloudy;
}

/// Text/emoji symbol for a condition. At night a clear sky is shown as a moon.
String conditionSymbol(WeatherCondition condition, {bool isDay = true}) => switch (condition) {
      WeatherCondition.clear => isDay ? '☀' : '🌙',
      WeatherCondition.partlyCloudy => isDay ? '⛅' : '☁',
      WeatherCondition.cloudy => '☁',
      WeatherCondition.fog => '🌫',
      WeatherCondition.drizzle => isDay ? '🌦' : '🌧',
      WeatherCondition.rain => '🌧',
      WeatherCondition.snow => '🌨',
      WeatherCondition.thunderstorm => '⛈',
    };
