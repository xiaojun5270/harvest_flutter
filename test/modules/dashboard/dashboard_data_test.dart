import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/modules/dashboard/model/dashboard_data.dart';

void main() {
  test('parses snake_case dashboard payload from api', () {
    final data = DashboardData.fromJson({
      'email_count': [
        {'key': 'mail@example.com', 'count': '3'},
      ],
      'username_count': [
        {'label': 'admin', 'value': 2},
      ],
      'total_uploaded': '1024',
      'total_downloaded': 2048,
      'total_seed_vol': '4096',
      'total_seeding': '5',
      'total_leeching': 6,
      'today_upload_increment': '7',
      'today_download_increment': 8,
      'total_published': '9',
      'upload_increment_data_list': [
        {'site': 'site-a', 'size': '10'},
      ],
      'download_increment_data_list': [
        {'name': 'site-b', 'value': 11},
      ],
      'upload_month_increment_data_list': [
        {
          'name': 'site-a',
          'value': [
            {
              'createdAt': '2026-05-27',
              'uploaded': '12',
              'downloaded': '13',
              'published': '14',
            },
          ],
        },
      ],
      'status_list': [
        {
          'name': 'site-a',
          'value': {
            'createdAt': '2026-05-27',
            'uploaded': '15',
            'downloaded': '16',
            'published': '17',
          },
        },
      ],
      'stack_chart_data_list': [
        {
          'name': 'site-a',
          'value': [
            {'createdAt': '2026-05-27', 'uploaded': '18', 'downloaded': '19'},
          ],
        },
      ],
      'seed_data_list': [
        {'label': 'site-a', 'total': '20'},
      ],
      'site_count': '21',
      'updated_at': '2026-05-27T12:00:00',
      'earliest_site': {
        'id': 1,
        'site': 'site-a',
        'time_join': '2020-01-01',
        'latest_active': '2026-05-27',
      },
    });

    expect(data.totalUploaded, 1024);
    expect(data.totalDownloaded, 2048);
    expect(data.totalSeedVol, 4096);
    expect(data.totalSeeding, 5);
    expect(data.totalLeeching, 6);
    expect(data.todayUploadIncrement, 7);
    expect(data.todayDownloadIncrement, 8);
    expect(data.totalPublished, 9);
    expect(data.siteCount, 21);
    expect(data.updatedAt, '2026-05-27T12:00:00');
    expect(data.earliestSite?.site, 'site-a');
    expect(data.emailCount.single.name, 'mail@example.com');
    expect(data.emailCount.single.value, 3);
    expect(data.uploadIncrementDataList.single.name, 'site-a');
    expect(data.uploadIncrementDataList.single.value, 10);
    expect(data.statusList.single.value.createdAt, '2026-05-27');
    expect(data.statusList.single.value.uploaded, 15);
    expect(data.stackChartDataList.single.value.single.downloaded, 19);
    expect(data.seedDataList.single.value, 20);
  });

  test('keeps camelCase dashboard cache payload compatible', () {
    final data = DashboardData.fromJson({
      'totalUploaded': 1,
      'totalDownloaded': 2,
      'siteCount': 3,
      'updatedAt': '2026-05-27T12:00:00',
    });

    expect(data.totalUploaded, 1);
    expect(data.totalDownloaded, 2);
    expect(data.siteCount, 3);
    expect(data.updatedAt, '2026-05-27T12:00:00');
  });
}
