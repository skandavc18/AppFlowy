import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';

/// How to use a dashboard template, in three steps, by template id. Empty
/// for a template that makes no dashboard.
List<String> templateGuide(String id) {
  final keys = switch (id.startsWith('board_') ? id.substring(6) : id) {
    'stocks' => const [
        LocaleKeys.templates_guide_stocks_first,
        LocaleKeys.templates_guide_stocks_second,
        LocaleKeys.templates_guide_stocks_third,
      ],
    'options' => const [
        LocaleKeys.templates_guide_options_first,
        LocaleKeys.templates_guide_options_second,
        LocaleKeys.templates_guide_options_third,
      ],
    'assets' => const [
        LocaleKeys.templates_guide_assets_first,
        LocaleKeys.templates_guide_assets_second,
        LocaleKeys.templates_guide_assets_third,
      ],
    'quotes' => const [
        LocaleKeys.templates_guide_quotes_first,
        LocaleKeys.templates_guide_quotes_second,
        LocaleKeys.templates_guide_quotes_third,
      ],
    'expenses' => const [
        LocaleKeys.templates_guide_expenses_first,
        LocaleKeys.templates_guide_expenses_second,
        LocaleKeys.templates_guide_expenses_third,
      ],
    'travel' => const [
        LocaleKeys.templates_guide_travel_first,
        LocaleKeys.templates_guide_travel_second,
        LocaleKeys.templates_guide_travel_third,
      ],
    'tracker' => const [
        LocaleKeys.templates_guide_tracker_first,
        LocaleKeys.templates_guide_tracker_second,
        LocaleKeys.templates_guide_tracker_third,
      ],
    'news_weather' => const [
        LocaleKeys.templates_guide_news_weather_first,
        LocaleKeys.templates_guide_news_weather_second,
        LocaleKeys.templates_guide_news_weather_third,
      ],
    'reading' => const [
        LocaleKeys.templates_guide_reading_first,
        LocaleKeys.templates_guide_reading_second,
        LocaleKeys.templates_guide_reading_third,
      ],
    'issues' => const [
        LocaleKeys.templates_guide_issues_first,
        LocaleKeys.templates_guide_issues_second,
        LocaleKeys.templates_guide_issues_third,
      ],
    'vedic_astrology' => const [
        LocaleKeys.templates_guide_vedic_astrology_first,
        LocaleKeys.templates_guide_vedic_astrology_second,
        LocaleKeys.templates_guide_vedic_astrology_third,
      ],
    'personal' => const [
        LocaleKeys.templates_guide_personal_first,
        LocaleKeys.templates_guide_personal_second,
        LocaleKeys.templates_guide_personal_third,
      ],
    'project' => const [
        LocaleKeys.templates_guide_project_first,
        LocaleKeys.templates_guide_project_second,
        LocaleKeys.templates_guide_project_third,
      ],
    'weekly' => const [
        LocaleKeys.templates_guide_weekly_first,
        LocaleKeys.templates_guide_weekly_second,
        LocaleKeys.templates_guide_weekly_third,
      ],
    'developer' => const [
        LocaleKeys.templates_guide_developer_first,
        LocaleKeys.templates_guide_developer_second,
        LocaleKeys.templates_guide_developer_third,
      ],
    'study' => const [
        LocaleKeys.templates_guide_study_first,
        LocaleKeys.templates_guide_study_second,
        LocaleKeys.templates_guide_study_third,
      ],
    'habits' => const [
        LocaleKeys.templates_guide_habits_first,
        LocaleKeys.templates_guide_habits_second,
        LocaleKeys.templates_guide_habits_third,
      ],
    'crm' => const [
        LocaleKeys.templates_guide_crm_first,
        LocaleKeys.templates_guide_crm_second,
        LocaleKeys.templates_guide_crm_third,
      ],
    'content' => const [
        LocaleKeys.templates_guide_content_first,
        LocaleKeys.templates_guide_content_second,
        LocaleKeys.templates_guide_content_third,
      ],
    'team' => const [
        LocaleKeys.templates_guide_team_first,
        LocaleKeys.templates_guide_team_second,
        LocaleKeys.templates_guide_team_third,
      ],
    'executive' => const [
        LocaleKeys.templates_guide_executive_first,
        LocaleKeys.templates_guide_executive_second,
        LocaleKeys.templates_guide_executive_third,
      ],
    _ => const <String>[],
  };
  return [for (final key in keys) key.tr()];
}
