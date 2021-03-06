#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

# These methods are mixed into the classes that can be considered a "context".
# See Context::ContextTypes below.
module Context

  module ContextTypes
    # These are all the classes that can be considered a "context":
    Account = ::Account
    Course = ::Course
    User = ::User
    Group = ::Group
  end
  
  module AssetTypes
    Announcement = ::Announcement
    AssessmentQuestion = ::AssessmentQuestion
    AssessmentQuestionBank = ::AssessmentQuestionBank
    Assignment = ::Assignment
    AssignmentGroup = ::AssignmentGroup
    Attachment = ::Attachment
    CalendarEvent = ::CalendarEvent
    Collaboration = ::Collaboration
    ContentTag = ::ContentTag
    ContextModule = ::ContextModule
    DiscussionEntry = ::DiscussionEntry
    DiscussionTopic = ::DiscussionTopic
    Folder = ::Folder
    LearningOutcome = ::LearningOutcome
    LearningOutcomeGroup = ::LearningOutcomeGroup
    MediaObject = ::MediaObject
    Quiz = ::Quiz
    QuizGroup = ::QuizGroup
    QuizQuestion = ::QuizQuestion
    QuizSubmission = ::QuizSubmission
    Rubric = ::Rubric
    RubricAssociation = ::RubricAssociation
    Submission = ::Submission
    WebConference = ::WebConference
    Wiki = ::Wiki
    WikiPage = ::WikiPage
    
    def self.get_for_string(str)
      if RUBY_VERSION >= "1.9."
        self.const_defined?(str, false) ? self.const_get(str, false) : nil
      else
        self.const_defined?(str) ? self.const_get(str) : nil
      end
    end
  end

  def add_aggregate_entries(entries, feed)
    if feed.feed_purpose == 'announcements'
      entries.each do |entry|
        user = entry.user || feed.user
        # If already existed and has been updated
        if entry.entry_changed? && entry.asset
          entry.asset.update_attributes(
            :title => entry.title,
            :message => entry.message
          )
        elsif !entry.asset
          announcement = self.announcements.build(
            :title => entry.title,
            :message => entry.message
          )
          announcement.external_feed_id = feed.id
          announcement.user = user
          announcement.save
          entry.update_attributes(:asset => announcement)
        end
      end
    elsif feed.feed_purpose == 'calendar'
      entries.each do |entry|
        user = entry.user || feed.user
        # If already existed and has been updated
        if entry.entry_changed? && entry.asset
          event = entry.asset
          event.attributes = {
            :title => entry.title,
            :description => entry.message,
            :start_at => entry.start_at,
            :end_at => entry.end_at
          }
          event.workflow_state = 'read_only'
          event.workflow_state = 'cancelled' if entry.cancelled?
          event.save
        elsif entry.active? && !entry.asset
          event = self.calendar_events.build(
            :title => entry.title,
            :description => entry.message,
            :start_at => entry.start_at,
            :end_at => entry.end_at
          )
          event.workflow_state = 'read_only'
          event.workflow_state = 'cancelled' if entry.cancelled?
          event.external_feed_id = feed.id
          event.save
          entry.update_attributes(:asset => event)
        end
      end
    end
  end
  
  def sorted_rubrics(user, context)
    associations = RubricAssociation.bookmarked.for_context_codes(context.asset_string).include_rubric
    associations.to_a.once_per(&:rubric_id).select{|r| r.rubric }.sort_by{|r| r.rubric.title || "zzzz" }
  end
  
  def rubric_contexts(user)
    context_codes = [self.asset_string]
    context_codes << ([user] + user.management_contexts).uniq.map(&:asset_string) if user
    context = self
    while context && context.respond_to?(:account) || context.respond_to?(:parent_account)
      context = context.respond_to?(:account) ? context.account : context.parent_account
      context_codes << context.asset_string if context
    end
    codes_order = {}
    context_codes.each_with_index{|c, idx| codes_order[c] = idx }
    associations = RubricAssociation.bookmarked.for_context_codes(context_codes).include_rubric
    associations = associations.to_a.select{|a| a.rubric }.once_per{|a| [a.rubric_id, a.context_code] }
    contexts = associations.group_by{|a| a.context_code }.map do |code, associations|
      context_name = associations.first.context_name
      res = {
        :rubrics => associations.length,
        :context_code => code,
        :name => context_name
      }
    end
    contexts.sort_by{|c| codes_order[c[:context_code]] || 999 }
  end
  
  def active_record_types
    @active_record_types ||= Rails.cache.fetch(['active_record_types', self].cache_key) do
      res = {}
      res[:files] = self.respond_to?(:attachments) && !self.attachments.active.empty?
      res[:modules] = self.respond_to?(:context_modules) && !self.context_modules.active.empty?
      res[:quizzes] = self.respond_to?(:quizzes) && !self.quizzes.active.empty?
      res[:assignments] = self.respond_to?(:assignments) && !self.assignments.active.empty?
      res[:pages] = self.respond_to?(:wiki) && self.wiki_id && !self.wiki.wiki_pages.active.empty?
      res[:conferences] = self.respond_to?(:web_conferences) && !self.web_conferences.active.empty?
      res[:announcements] = self.respond_to?(:announcements) && !self.announcements.active.empty?
      res[:outcomes] = self.respond_to?(:has_outcomes?) && self.has_outcomes?
      res
    end
  end
  
  def allow_wiki_comments
    false
  end

  def find_asset(asset_string, allowed_types=nil)
    return nil unless asset_string
    res = Context.find_asset_by_asset_string(asset_string, self, allowed_types)
    res = nil if res.respond_to?(:deleted?) && res.deleted?
    res
  end
  
  def self.find_by_asset_string(string)
    opts = string.split("_")
    id = opts.pop
    if ContextTypes.const_defined?(opts.join('_').classify)
      type = ContextTypes.const_get(opts.join('_').classify)
      context = type.find(id)
    else
      nil
    end
  rescue => e
    nil
  end
  
  def self.find_asset_by_asset_string(string, context=nil, allowed_types=nil)
    opts = string.split("_")
    id = opts.pop
    type = opts.join('_').classify
    klass = nil
    if AssetTypes.const_defined?(type)
      klass = AssetTypes.const_get(type)
    end
    klass = nil if allowed_types && !allowed_types.include?(klass.to_s.underscore.to_sym)
    return nil unless klass
    res = nil
    if klass == WikiPage
      res = context.wiki.wiki_pages.find_by_id(id)
    elsif (klass.column_names & ['context_id', 'context_type']).length == 2
      res = klass.find_by_context_id_and_context_type_and_id(context.id, context.class.to_s, id)
    else
      res = klass.find_by_id(id)
      res = nil if context && res && res.respond_to?(:context) && res.context != context
    end
    res
  rescue => e
    nil
  end
  
  def is_a_context?
    true
  end
end
