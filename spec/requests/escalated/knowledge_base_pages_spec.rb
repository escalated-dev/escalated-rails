# frozen_string_literal: true

require 'rails_helper'

# The knowledge base screens the shared frontend drives: the admin article
# list and form (src/pages/Admin/KnowledgeBase/Articles/*), and the customer
# reader (src/pages/Customer/KnowledgeBase/*). Props and bodies follow
# escalated-laravel's ArticleController and Customer\KnowledgeBaseController.
RSpec.describe 'Knowledge base pages', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-kb-pages@example.test') }
  let(:customer) { create(:user, email: 'reader-kb-pages@example.test') }
  let(:signed_in) { admin }
  let!(:category) { Escalated::ArticleCategory.create!(name: 'Billing', slug: 'billing', description: 'Money things') }

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user) { signed_in }
  end

  def article(**attributes)
    Escalated::Article.create!({ title: 'Refunds', slug: 'refunds', body: '<p>How refunds work.</p>',
                                 status: 'published', published_at: 1.day.ago, category: category }
                               .merge(attributes))
  end

  def set_setting(key, value)
    Escalated::EscalatedSetting.set(key, value)
  end

  describe 'admin articles' do
    let(:body) do
      { title: 'Changing plans', slug: '', body: '<p>Steps.</p>', status: 'published', category_id: category.id }
    end

    it 'lists articles with the fields the list reads' do
      row = article(view_count: 7, helpful_count: 3)

      page = expect_screen('/support/admin/articles', 'Escalated/Admin/KnowledgeBase/Articles/Index')

      expect(page.dig('props', 'articles', 'data').sole).to include(
        'id' => row.id, 'title' => 'Refunds', 'status' => 'published', 'view_count' => 7, 'helpful_count' => 3,
        'category' => include('id' => category.id, 'name' => 'Billing')
      )
      expect(page.dig('props', 'articles')).to include('last_page' => 1, 'links' => [])
      expect(page.dig('props', 'categories')).to eq([{ 'id' => category.id, 'name' => 'Billing' }])
    end

    it 'renders the empty form with the categories to file under' do
      page = expect_screen('/support/admin/articles/new', 'Escalated/Admin/KnowledgeBase/Articles/Form')

      expect(page.dig('props', 'article')).to be_nil
      expect(page.dig('props', 'categories')).to eq([{ 'id' => category.id, 'name' => 'Billing' }])
    end

    it 'renders the form for an existing article' do
      row = article

      page = expect_screen("/support/admin/articles/#{row.id}/edit", 'Escalated/Admin/KnowledgeBase/Articles/Form')

      expect(page.dig('props', 'article')).to include(
        'id' => row.id, 'title' => 'Refunds', 'slug' => 'refunds', 'body' => '<p>How refunds work.</p>',
        'status' => 'published', 'category_id' => category.id
      )
    end

    it 'creates an article, deriving the slug and stamping publication' do
      expect { inertia_visit(:post, '/support/admin/articles', body) }.to change(Escalated::Article, :count).by(1)

      expect(response).to redirect_to('/support/admin/articles')
      created = Escalated::Article.last
      expect(created).to have_attributes(title: 'Changing plans', slug: 'changing-plans', body: '<p>Steps.</p>',
                                         status: 'published', category_id: category.id, author_id: admin.id)
      expect(created.published_at).to be_present
    end

    it 'updates an article and keeps its first publication time' do
      published_at = 3.days.ago.change(usec: 0)
      row = article(published_at: published_at)

      inertia_visit(:put, "/support/admin/articles/#{row.id}", body.merge(slug: 'plans', category_id: ''))

      expect(response).to redirect_to('/support/admin/articles')
      expect(row.reload).to have_attributes(title: 'Changing plans', slug: 'plans', category_id: nil)
      expect(row.published_at).to be_within(1.second).of(published_at)
    end

    it 'refuses an article with no title, an unknown status or a missing category' do
      inertia_visit(:post, '/support/admin/articles', body.merge(title: '', status: 'archived', category_id: 0),
                    referer: '/support/admin/articles/new')

      expect(response).to redirect_to('/support/admin/articles/new')
      expect(session[:inertia_errors].keys).to include('title', 'status', 'category_id')
      expect(Escalated::Article.count).to eq(0)
    end
  end

  describe 'customer reader' do
    let(:signed_in) { customer }

    it 'lists published articles and the categories with their published counts' do
      shown = article
      article(title: 'Draft', slug: 'draft', status: 'draft', published_at: nil)

      page = expect_screen('/support/customer/kb', 'Escalated/Customer/KnowledgeBase/Index')

      expect(page.dig('props', 'articles', 'data').sole).to include(
        'id' => shown.id, 'title' => 'Refunds', 'slug' => 'refunds', 'view_count' => 0,
        'category' => include('name' => 'Billing')
      )
      expect(page.dig('props', 'articles')).to include('last_page' => 1)
      expect(page.dig('props', 'categories').sole).to include(
        'id' => category.id, 'name' => 'Billing', 'description' => 'Money things', 'articles_count' => 1
      )
      expect(page.dig('props', 'filters')).to eq({})
    end

    it 'filters by search and category' do
      article
      other = Escalated::ArticleCategory.create!(name: 'Shipping', slug: 'shipping')
      article(title: 'Tracking a parcel', slug: 'tracking', category: other)

      get '/support/customer/kb', params: { search: 'parcel', category: other.id }

      page = inertia_page
      expect(page.dig('props', 'articles', 'data').pluck('slug')).to eq(['tracking'])
      expect(page.dig('props', 'filters')).to eq('search' => 'parcel', 'category' => other.id.to_s)
    end

    it 'shows an article with related reading and counts the view' do
      shown = article
      article(title: 'Partial refunds', slug: 'partial-refunds')

      page = expect_screen('/support/customer/kb/refunds', 'Escalated/Customer/KnowledgeBase/Article')

      expect(page.dig('props', 'article')).to include(
        'id' => shown.id, 'title' => 'Refunds', 'slug' => 'refunds', 'body' => '<p>How refunds work.</p>',
        'category' => include('id' => category.id, 'name' => 'Billing')
      )
      expect(page.dig('props', 'article', 'published_at')).to be_present
      expect(page.dig('props', 'related')).to eq([{ 'id' => Escalated::Article.find_by(slug: 'partial-refunds').id,
                                                    'title' => 'Partial refunds', 'slug' => 'partial-refunds' }])
      expect(page.dig('props', 'feedbackEnabled')).to be(true)
      expect(shown.reload.view_count).to eq(1)
    end

    it 'does not show a draft' do
      article(status: 'draft', published_at: nil)

      get '/support/customer/kb/refunds'

      expect(response).to have_http_status(:not_found)
    end

    it 'records feedback and goes back to the article' do
      shown = article

      inertia_visit(:post, '/support/customer/kb/refunds/feedback', { helpful: true },
                    referer: '/support/customer/kb/refunds')
      expect(response).to redirect_to('/support/customer/kb/refunds')

      inertia_visit(:post, '/support/customer/kb/refunds/feedback', { helpful: false },
                    referer: '/support/customer/kb/refunds')

      expect(shown.reload).to have_attributes(helpful_count: 1, not_helpful_count: 1)
    end

    it 'refuses feedback when feedback is off' do
      article
      set_setting('knowledge_base_feedback_enabled', '0')

      inertia_visit(:post, '/support/customer/kb/refunds/feedback', { helpful: true })

      expect(response).to have_http_status(:not_found)
    end

    it 'is not there when the knowledge base is off' do
      set_setting('knowledge_base_enabled', '0')

      get '/support/customer/kb'

      expect(response).to have_http_status(:not_found)
    end

    context 'when signed out' do
      let(:signed_in) { nil }

      it 'is readable while the knowledge base is public' do
        article

        expect_screen('/support/customer/kb', 'Escalated/Customer/KnowledgeBase/Index')
      end

      it 'asks for a sign-in once it is not' do
        set_setting('knowledge_base_public', '0')

        get '/support/customer/kb'

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
