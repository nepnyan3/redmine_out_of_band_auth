Redmine::Plugin.register :redmine_out_of_band_auth do
  name 'Redmine Out of Band Authentication plugin'
  author 'Matsukei Co.,Ltd'
  description 'Redmine plugin that provides Out of Band authentication by email.'
  version '2.0.0'
  requires_redmine version_or_higher: '7.0.0'
  url 'https://github.com/matsukei/redmine_out_of_band_auth'
  author_url 'http://www.matsukei.co.jp/'
end

OutOfBandAuth.prepare
