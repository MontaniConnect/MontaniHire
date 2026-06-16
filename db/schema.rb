# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_16_064211) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "candidates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "cv_analysis_id"
    t.datetime "hired_at"
    t.bigint "job_role_id"
    t.string "name", null: false
    t.boolean "no_show", default: false, null: false
    t.datetime "outcome_confirmed_at"
    t.text "outcome_note"
    t.string "pipeline_stage", default: "cv_review", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "video_analysis_id"
    t.index ["cv_analysis_id"], name: "index_candidates_on_cv_analysis_id"
    t.index ["job_role_id"], name: "index_candidates_on_job_role_id"
    t.index ["user_id"], name: "index_candidates_on_user_id"
    t.index ["video_analysis_id"], name: "index_candidates_on_video_analysis_id"
  end

  create_table "cv_analyses", force: :cascade do |t|
    t.string "candidate_name"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "extracted_text"
    t.bigint "job_role_id"
    t.string "prompt_version"
    t.decimal "score", precision: 4, scale: 2
    t.string "status", default: "pending", null: false
    t.jsonb "structured_feedback", default: {}
    t.text "summary"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["job_role_id"], name: "index_cv_analyses_on_job_role_id"
    t.index ["status"], name: "index_cv_analyses_on_status"
    t.index ["user_id"], name: "index_cv_analyses_on_user_id"
  end

  create_table "job_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "experience_level", default: "mid", null: false
    t.jsonb "must_have_requirements", default: [], null: false
    t.jsonb "nice_to_have_requirements", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_job_roles_on_user_id"
  end

  create_table "salary_benchmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "salary_insights", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "shortlist_items", force: :cascade do |t|
    t.bigint "candidate_id"
    t.text "client_comment"
    t.string "client_status", default: "pending"
    t.datetime "created_at", null: false
    t.bigint "cv_analysis_id"
    t.bigint "shareable_id"
    t.string "shareable_type"
    t.bigint "shortlist_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_analysis_id"
    t.index ["candidate_id"], name: "index_shortlist_items_on_candidate_id"
    t.index ["cv_analysis_id"], name: "index_shortlist_items_on_cv_analysis_id"
    t.index ["shareable_type", "shareable_id"], name: "index_shortlist_items_on_shareable"
    t.index ["shortlist_id", "shareable_type", "shareable_id"], name: "index_shortlist_items_on_shortlist_and_shareable", unique: true
    t.index ["shortlist_id"], name: "index_shortlist_items_on_shortlist_id"
    t.index ["video_analysis_id"], name: "index_shortlist_items_on_video_analysis_id"
  end

  create_table "shortlists", force: :cascade do |t|
    t.string "client_email", null: false
    t.datetime "created_at", null: false
    t.text "message"
    t.string "title", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_shortlists_on_token", unique: true
    t.index ["user_id"], name: "index_shortlists_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "video_analyses", force: :cascade do |t|
    t.string "assembly_transcript_id"
    t.string "candidate_name"
    t.text "cleaned_transcript"
    t.datetime "created_at", null: false
    t.string "drive_file_id"
    t.string "drive_file_name"
    t.text "error_message"
    t.bigint "job_role_id"
    t.string "prompt_version"
    t.decimal "score", precision: 4, scale: 2
    t.string "status", default: "pending", null: false
    t.jsonb "structured_feedback", default: {}
    t.text "summary"
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["assembly_transcript_id"], name: "index_video_analyses_on_assembly_transcript_id"
    t.index ["drive_file_id"], name: "index_video_analyses_on_drive_file_id"
    t.index ["job_role_id"], name: "index_video_analyses_on_job_role_id"
    t.index ["status"], name: "index_video_analyses_on_status"
    t.index ["user_id"], name: "index_video_analyses_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "candidates", "job_roles"
  add_foreign_key "candidates", "users"
  add_foreign_key "cv_analyses", "job_roles"
  add_foreign_key "cv_analyses", "users"
  add_foreign_key "job_roles", "users"
  add_foreign_key "shortlist_items", "candidates"
  add_foreign_key "shortlist_items", "shortlists"
  add_foreign_key "shortlists", "users"
  add_foreign_key "video_analyses", "job_roles"
  add_foreign_key "video_analyses", "users"
end
