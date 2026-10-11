<?php

namespace Tests\Feature;

use App\Models\AcademicYear;
use App\Models\LearningMaterial;
use App\Models\SchoolClass;
use App\Models\Subject;
use App\Models\User;
use App\Services\GoogleDriveStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class LearningMaterialFileTest extends TestCase
{
    use RefreshDatabase;

    public function test_teacher_uploads_pdf_and_enrolled_student_can_view_and_download_it(): void
    {
        Storage::fake('local');
        $this->configureSupabase();
        [$teacher, $student, $class, $subject] = $this->createClassWithStudent();
        Http::fake(function ($request) {
            if ($request->method() === 'POST' && str_ends_with($request->url(), '/storage/v1/bucket')) {
                return Http::response(['message' => 'Bucket already exists'], 409);
            }
            if ($request->method() === 'POST' && str_contains($request->url(), '/storage/v1/object/materials/')) {
                return Http::response(['Key' => 'materials/file.pdf']);
            }
            if ($request->method() === 'GET' && str_contains($request->url(), '/storage/v1/object/materials/')) {
                return Http::response('pdf-content');
            }

            return Http::response([], 200);
        });

        $this->actingAs($teacher)->post(route('teacher.materials.store'), [
            'title' => 'Algebra Notes',
            'school_class_id' => $class->id,
            'subject_id' => $subject->id,
            'file' => UploadedFile::fake()->create('algebra-notes.pdf', 12, 'application/pdf'),
        ])->assertRedirect();

        $material = LearningMaterial::firstOrFail();
        $this->assertNull($material->google_drive_file_id);
        $this->assertNotNull($material->file_path);
        $this->assertSame('supabase', $material->storage_disk);
        $this->assertSame('algebra-notes.pdf', $material->original_file_name);
        $this->assertSame(12 * 1024, $material->file_size);
        $this->assertSame('application/pdf', $material->file_type);
        $this->assertStringContainsString("/api/v1/materials/{$material->id}/file", $material->file_url);

        $view = $this->actingAs($student)->get(route('student.materials.file', $material));
        $view->assertOk();
        $view->assertHeader('Content-Type', 'application/pdf');
        $this->assertStringContainsString('inline', strtolower((string) $view->headers->get('Content-Disposition')));

        $download = $this->actingAs($student)->get(route('student.materials.file', [
            'material' => $material,
            'download' => 1,
        ]));
        $download->assertOk();
        $this->assertStringContainsString('attachment', strtolower((string) $download->headers->get('Content-Disposition')));
        $this->assertStringContainsString('algebra-notes.pdf', (string) $download->headers->get('Content-Disposition'));
    }

    public function test_student_materials_are_grouped_and_filtered_by_the_enrolled_class_subject(): void
    {
        [$teacher, $student, $biologyClass, $biology] = $this->createClassWithStudent();
        $teacher->update(['first_name' => 'Taylor', 'middle_name' => null, 'last_name' => 'Teacher']);
        $biology->update(['name' => 'Biology']);

        $year = AcademicYear::factory()->create();
        $chemistry = Subject::factory()->create([
            'name' => 'Chemistry',
            'teacher_id' => $teacher->id,
            'academic_year_id' => $year->id,
        ]);
        $chemistryClass = SchoolClass::create([
            'name' => 'Chemistry 11',
            'section' => 'B',
            'grade_level' => '11',
            'subject_id' => $chemistry->id,
            'teacher_id' => $teacher->id,
            'academic_year_id' => $year->id,
        ]);
        $student->enrolledClasses()->attach($chemistryClass->id);

        $otherSubject = Subject::factory()->create([
            'teacher_id' => $teacher->id,
            'academic_year_id' => $year->id,
        ]);
        $otherClass = SchoolClass::create([
            'name' => 'History 11',
            'section' => 'C',
            'grade_level' => '11',
            'subject_id' => $otherSubject->id,
            'teacher_id' => $teacher->id,
            'academic_year_id' => $year->id,
        ]);

        $biologyMaterial = LearningMaterial::create([
            'title' => 'Cell Structure Notes',
            'file_path' => 'materials/cell-structure.pdf',
            'file_type' => 'application/pdf',
            'subject_id' => $biology->id,
            'school_class_id' => $biologyClass->id,
            'uploaded_by' => $teacher->id,
        ]);
        LearningMaterial::create([
            'title' => 'Chemical Reactions Video',
            'file_path' => 'materials/reactions.mp4',
            'file_type' => 'video/mp4',
            'subject_id' => $chemistry->id,
            'school_class_id' => $chemistryClass->id,
            'uploaded_by' => $teacher->id,
        ]);
        $wrongSubjectMaterial = LearningMaterial::create([
            'title' => 'Wrong Subject Material',
            'file_path' => 'materials/wrong-subject.pdf',
            'file_type' => 'application/pdf',
            'subject_id' => $chemistry->id,
            'school_class_id' => $biologyClass->id,
            'uploaded_by' => $teacher->id,
        ]);
        LearningMaterial::create([
            'title' => 'Not Enrolled Material',
            'file_path' => 'materials/not-enrolled.pdf',
            'file_type' => 'application/pdf',
            'subject_id' => $otherSubject->id,
            'school_class_id' => $otherClass->id,
            'uploaded_by' => $teacher->id,
        ]);

        $response = $this->actingAs($student)
            ->get(route('student.materials.index'))
            ->assertOk()
            ->assertSee('Biology')
            ->assertSee('Chemistry')
            ->assertSee('Cell Structure Notes')
            ->assertSee('Chemical Reactions Video')
            ->assertSee('Taylor Teacher')
            ->assertSee($biologyMaterial->created_at->format('M j, Y'))
            ->assertDontSee('Wrong Subject Material')
            ->assertDontSee('Not Enrolled Material');

        $html = $response->getContent();
        preg_match('/<section\b[^>]*aria-labelledby="subject-'.$biology->id.'"[^>]*>(.*?)<\/section>/s', $html, $biologySection);
        preg_match('/<section\b[^>]*aria-labelledby="subject-'.$chemistry->id.'"[^>]*>(.*?)<\/section>/s', $html, $chemistrySection);
        $this->assertNotEmpty($biologySection);
        $this->assertNotEmpty($chemistrySection);
        $this->assertStringContainsString('Cell Structure Notes', $biologySection[1]);
        $this->assertStringNotContainsString('Chemical Reactions Video', $biologySection[1]);
        $this->assertStringContainsString('Chemical Reactions Video', $chemistrySection[1]);
        $this->assertStringNotContainsString('Cell Structure Notes', $chemistrySection[1]);

        $this->actingAs($student)
            ->get(route('student.materials.file', $wrongSubjectMaterial))
            ->assertForbidden();

        $token = $student->createToken('subject-materials-test')->plainTextToken;
        $this->withToken($token)
            ->getJson('/api/v1/materials')
            ->assertOk()
            ->assertJsonFragment(['title' => 'Cell Structure Notes'])
            ->assertJsonFragment(['title' => 'Chemical Reactions Video'])
            ->assertJsonMissing(['title' => 'Wrong Subject Material'])
            ->assertJsonMissing(['title' => 'Not Enrolled Material']);

        $response = $this->get(route('student.materials.index', ['subject_id' => $biology->id]));
        $response->assertOk()
            ->assertSee('Cell Structure Notes')
            ->assertDontSee('Chemical Reactions Video')
            ->assertDontSee('Wrong Subject Material');

        $response = $this->get(route('student.materials.index', ['search' => 'Chemistry']));
        $response->assertOk()
            ->assertSee('Chemical Reactions Video')
            ->assertDontSee('Cell Structure Notes');
    }

    public function test_teacher_cannot_upload_a_material_to_a_subject_that_does_not_belong_to_the_class(): void
    {
        [$teacher, , $class, $subject] = $this->createClassWithStudent();
        $wrongSubject = Subject::factory()->create([
            'teacher_id' => $teacher->id,
            'academic_year_id' => $subject->academic_year_id,
        ]);

        $this->actingAs($teacher)
            ->post(route('teacher.materials.store'), [
                'title' => 'Misassigned Material',
                'school_class_id' => $class->id,
                'subject_id' => $wrongSubject->id,
                'file' => UploadedFile::fake()->create('misassigned.pdf', 12, 'application/pdf'),
            ])
            ->assertForbidden();

        $this->assertDatabaseMissing('learning_materials', ['title' => 'Misassigned Material']);
    }

    public function test_teacher_can_replace_a_material_file_in_supabase_storage(): void
    {
        $this->configureSupabase();
        [$teacher, , $class, $subject] = $this->createClassWithStudent();
        $material = LearningMaterial::create([
            'title' => 'Existing Notes',
            'file_path' => 'old.pdf',
            'storage_disk' => 'supabase',
            'original_file_name' => 'old.pdf',
            'file_type' => 'application/pdf',
            'file_size' => 10,
            'subject_id' => $subject->id,
            'school_class_id' => $class->id,
            'uploaded_by' => $teacher->id,
        ]);
        Http::fake(function ($request) {
            if ($request->method() === 'POST' && str_ends_with($request->url(), '/storage/v1/bucket')) {
                return Http::response(['message' => 'Bucket already exists'], 409);
            }

            return Http::response([], 200);
        });

        $this->actingAs($teacher)->post(route('teacher.materials.replace', $material), [
            'title' => 'Updated Notes',
            'description' => 'Revised study notes',
            'school_class_id' => $class->id,
            'subject_id' => $subject->id,
            'file' => UploadedFile::fake()->create('updated.pdf', 25, 'application/pdf'),
        ])->assertRedirect();

        $material->refresh();
        $this->assertNull($material->google_drive_file_id);
        $this->assertSame('supabase', $material->storage_disk);
        $this->assertNotSame('old.pdf', $material->file_path);
        $this->assertSame('updated.pdf', $material->original_file_name);
        $this->assertSame(25 * 1024, $material->file_size);
        $this->assertSame('Updated Notes', $material->title);
        $this->assertSame('Revised study notes', $material->description);
        $this->assertSame('supabase', $material->storage_disk);
        $this->actingAs($teacher)
            ->get(route('teacher.materials.index'))
            ->assertOk()
            ->assertInertia(fn ($page) => $page
                ->component('Teacher/Materials/Index')
                ->where('materials.data.0.title', 'Updated Notes')
                ->where('materials.data.0.description', 'Revised study notes')
                ->where('materials.data.0.original_file_name', 'updated.pdf'));

        Http::assertSent(fn ($request) => $request->method() === 'DELETE'
            && json_decode($request->body(), true)['prefixes'][0] === 'old.pdf');

        $this->actingAs($teacher)
            ->delete(route('teacher.materials.destroy', $material))
            ->assertRedirect();

        $this->assertSoftDeleted('learning_materials', ['id' => $material->id]);
        Http::assertSent(fn ($request) => $request->method() === 'DELETE'
            && json_decode($request->body(), true)['prefixes'][0] === $material->file_path);
    }

    public function test_teacher_can_update_material_details_without_replacing_its_file(): void
    {
        [$teacher, , $class, $subject] = $this->createClassWithStudent();
        $material = LearningMaterial::create([
            'title' => 'Original Notes',
            'description' => 'Original description',
            'file_path' => 'materials/original.pdf',
            'storage_disk' => 'local',
            'original_file_name' => 'original.pdf',
            'file_type' => 'application/pdf',
            'file_size' => 10,
            'subject_id' => $subject->id,
            'school_class_id' => $class->id,
            'uploaded_by' => $teacher->id,
        ]);

        $this->actingAs($teacher)
            ->post(route('teacher.materials.replace', $material), [
                'title' => 'Revised Notes',
                'description' => 'Revised description',
                'school_class_id' => $class->id,
                'subject_id' => $subject->id,
            ])
            ->assertRedirect()
            ->assertSessionHas('success', 'Material updated.');

        $material->refresh();
        $this->assertSame('Revised Notes', $material->title);
        $this->assertSame('Revised description', $material->description);
        $this->assertSame('materials/original.pdf', $material->file_path);
        $this->assertSame('original.pdf', $material->original_file_name);

        $this->actingAs($teacher)
            ->get(route('teacher.materials.index'))
            ->assertOk()
            ->assertInertia(fn ($page) => $page
                ->component('Teacher/Materials/Index')
                ->where('materials.data.0.title', 'Revised Notes')
                ->where('materials.data.0.description', 'Revised description')
                ->where('materials.data.0.original_file_name', 'original.pdf'));
    }

    public function test_teacher_upload_failure_is_reported_without_creating_database_metadata(): void
    {
        [$teacher, , $class, $subject] = $this->createClassWithStudent();
        config([
            'services.supabase.url' => 'https://supabase.test',
            'services.supabase.service_role_key' => null,
        ]);

        $this->actingAs($teacher)->post(route('teacher.materials.store'), [
            'title' => 'Algebra Notes',
            'school_class_id' => $class->id,
            'subject_id' => $subject->id,
            'file' => UploadedFile::fake()->create('algebra-notes.pdf', 12, 'application/pdf'),
        ])->assertRedirect()
            ->assertSessionHasErrors('file');

        $this->assertDatabaseCount('learning_materials', 0);
    }

    public function test_teacher_deletes_the_drive_file_and_soft_deletes_its_metadata(): void
    {
        [$teacher, , $class, $subject] = $this->createClassWithStudent();
        $material = LearningMaterial::create([
            'title' => 'Study Guide',
            'google_drive_file_id' => 'drive-to-delete',
            'original_file_name' => 'study-guide.pdf',
            'file_type' => 'application/pdf',
            'file_size' => 20,
            'subject_id' => $subject->id,
            'school_class_id' => $class->id,
            'uploaded_by' => $teacher->id,
        ]);
        $drive = \Mockery::mock(GoogleDriveStorage::class);
        $drive->shouldReceive('delete')->once()->with('drive-to-delete');
        $this->app->instance(GoogleDriveStorage::class, $drive);

        $this->actingAs($teacher)
            ->delete(route('teacher.materials.destroy', $material))
            ->assertRedirect();

        $this->assertSoftDeleted('learning_materials', ['id' => $material->id]);
    }

    public function test_pdf_image_video_and_presentation_files_are_served_inline_and_as_downloads(): void
    {
        Storage::fake('local');
        [, $student, $class, $subject] = $this->createClassWithStudent();

        $files = [
            ['notes.pdf', 'application/pdf'],
            ['diagram.png', 'image/png'],
            ['lesson.mp4', 'video/mp4'],
            ['slides.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'],
        ];

        foreach ($files as [$path, $mimeType]) {
            Storage::disk('local')->put("materials/{$path}", 'material-content');
            $material = LearningMaterial::create([
                'title' => pathinfo($path, PATHINFO_FILENAME),
                'file_path' => "materials/{$path}",
                'file_type' => $mimeType,
                'subject_id' => $subject->id,
                'school_class_id' => $class->id,
                'uploaded_by' => $class->teacher_id,
            ]);

            $view = $this->actingAs($student)->get(route('student.materials.file', $material));
            $view->assertOk();
            $view->assertHeader('Content-Type', $mimeType);
            $this->assertStringContainsString('inline', strtolower((string) $view->headers->get('Content-Disposition')));

            $download = $this->actingAs($student)->get(route('student.materials.file', [
                'material' => $material,
                'download' => 1,
            ]));
            $download->assertOk();
            $download->assertHeader('Content-Type', $mimeType);
            $this->assertStringContainsString('attachment', strtolower((string) $download->headers->get('Content-Disposition')));
        }
    }

    public function test_view_infers_browser_mime_type_when_cloud_metadata_is_generic(): void
    {
        $this->configureSupabase();
        [, $student, $class, $subject] = $this->createClassWithStudent();
        Http::fake([
            'https://supabase.test/storage/v1/object/materials/*' => Http::response('material-content'),
        ]);

        foreach ([
            ['notes.pdf', 'application/pdf'],
            ['diagram.png', 'image/png'],
            ['lesson.mp4', 'video/mp4'],
        ] as [$filename, $mimeType]) {
            $material = LearningMaterial::create([
                'title' => pathinfo($filename, PATHINFO_FILENAME),
                'file_path' => 'materials/'.Str::uuid(),
                'storage_disk' => 'supabase',
                'original_file_name' => $filename,
                'file_type' => 'application/octet-stream',
                'subject_id' => $subject->id,
                'school_class_id' => $class->id,
                'uploaded_by' => $class->teacher_id,
            ]);

            $this->actingAs($student)
                ->get(route('student.materials.file', $material))
                ->assertOk()
                ->assertHeader('Content-Type', $mimeType)
                ->assertHeader('Content-Disposition', 'inline; filename='.$filename);
        }
    }

    public function test_pdf_view_normalizes_pdf_mime_type_and_filename_for_inline_display(): void
    {
        Storage::fake('local');
        [, $student, $class, $subject] = $this->createClassWithStudent();
        Storage::disk('local')->put('materials/lecture', 'pdf-content');
        $material = LearningMaterial::create([
            'title' => 'Lecture Notes',
            'file_path' => 'materials/lecture',
            'file_type' => 'application/x-pdf',
            'subject_id' => $subject->id,
            'school_class_id' => $class->id,
            'uploaded_by' => $class->teacher_id,
        ]);

        $view = $this->actingAs($student)
            ->get(route('student.materials.file', $material))
            ->assertOk()
            ->assertHeader('Content-Type', 'application/pdf');
        $this->assertStringStartsWith(
            'inline;',
            strtolower((string) $view->headers->get('Content-Disposition')),
        );
        $this->assertStringContainsString(
            'lecture notes.pdf',
            strtolower((string) $view->headers->get('Content-Disposition')),
        );

        $download = $this->get(route('student.materials.file', [
            'material' => $material,
            'download' => 1,
        ]));
        $download->assertOk()
            ->assertHeader('Content-Type', 'application/pdf');
        $this->assertStringStartsWith(
            'attachment;',
            strtolower((string) $download->headers->get('Content-Disposition')),
        );
    }

    public function test_material_view_opens_in_a_new_tab_and_download_remains_separate(): void
    {
        Storage::fake('local');
        [, $student, $class, $subject] = $this->createClassWithStudent();
        Storage::disk('local')->put('materials/notes.pdf', 'pdf-content');
        $material = LearningMaterial::create([
            'title' => 'Notes',
            'file_path' => 'materials/notes.pdf',
            'file_type' => 'application/pdf',
            'subject_id' => $subject->id,
            'school_class_id' => $class->id,
            'uploaded_by' => $class->teacher_id,
        ]);

        $this->actingAs($student)
            ->get(route('student.materials.index'))
            ->assertOk()
            ->assertSee(route('student.materials.file', $material), false)
            ->assertSee('target="_blank"', false)
            ->assertSee('rel="noopener"', false)
            ->assertSee(route('student.materials.file', [
                'material' => $material,
                'download' => 1,
            ]), false);
    }

    public function test_students_cannot_access_other_classes_files_and_missing_files_return_404(): void
    {
        Storage::fake('local');
        [$teacher, $student, $class, $subject] = $this->createClassWithStudent();
        $otherClass = SchoolClass::create([
            'name' => 'Chemistry 11',
            'section' => 'B',
            'grade_level' => '11',
            'subject_id' => $subject->id,
            'teacher_id' => $teacher->id,
            'academic_year_id' => $class->academic_year_id,
        ]);
        Storage::disk('local')->put('materials/private.pdf', 'private-content');

        $material = LearningMaterial::create([
            'title' => 'Private Notes',
            'file_path' => 'materials/private.pdf',
            'file_type' => 'application/pdf',
            'subject_id' => $subject->id,
            'school_class_id' => $otherClass->id,
            'uploaded_by' => $teacher->id,
        ]);

        $this->actingAs($student)
            ->get(route('student.materials.file', $material))
            ->assertForbidden();

        $student->enrolledClasses()->attach($otherClass->id);
        Storage::disk('local')->delete($material->file_path);

        $this->get(route('student.materials.file', $material))->assertNotFound();
    }

    public function test_api_file_endpoint_requires_enrollment_and_serves_the_protected_file(): void
    {
        Storage::fake('local');
        [, $student, $class, $subject] = $this->createClassWithStudent();
        Storage::disk('local')->put('materials/api.pdf', 'api-pdf-content');
        $material = LearningMaterial::create([
            'title' => 'API Notes',
            'file_path' => 'materials/api.pdf',
            'file_type' => 'application/pdf',
            'subject_id' => $subject->id,
            'school_class_id' => $class->id,
            'uploaded_by' => $class->teacher_id,
        ]);

        $token = $student->createToken('material-test')->plainTextToken;
        $this->withToken($token)
            ->getJson(route('api.v1.materials.file', $material))
            ->assertOk()
            ->assertHeader('Content-Type', 'application/pdf');

        $response = $this->withToken($token)
            ->getJson(route('api.v1.materials.download', $material))
            ->assertOk()
            ->assertJsonPath('data.file_url', route('api.v1.materials.file', $material))
            ->assertJsonPath('data.material.id', $material->id);

        $viewUrl = $response->json('data.view_url');
        $downloadUrl = $response->json('data.download_url');
        $this->assertStringContainsString('/student/materials/'.$material->id.'/secure-file?', $viewUrl);
        $this->assertStringContainsString('signature=', $viewUrl);
        $this->assertStringContainsString('signature=', $downloadUrl);
        $view = $this->get($viewUrl)->assertOk();
        $this->assertStringContainsString(
            'inline',
            strtolower((string) $view->headers->get('Content-Disposition')),
        );
        $signedDownload = $this->get($downloadUrl);
        $signedDownload->assertOk();
        $this->assertStringContainsString('attachment', strtolower((string) $signedDownload->headers->get('Content-Disposition')));

        $student->enrolledClasses()->detach($class->id);
        $this->get($viewUrl)->assertForbidden();
    }

    /**
     * @return array{User, User, SchoolClass, Subject}
     */
    private function createClassWithStudent(): array
    {
        $teacher = User::factory()->teacher()->create();
        $student = User::factory()->student()->create();
        $year = AcademicYear::factory()->create();
        $subject = Subject::factory()->create([
            'teacher_id' => $teacher->id,
            'academic_year_id' => $year->id,
        ]);
        $class = SchoolClass::create([
            'name' => 'Biology 11',
            'section' => 'A',
            'grade_level' => '11',
            'subject_id' => $subject->id,
            'teacher_id' => $teacher->id,
            'academic_year_id' => $year->id,
        ]);
        $student->enrolledClasses()->attach($class->id);

        return [$teacher, $student, $class, $subject];
    }

    private function configureSupabase(): void
    {
        config([
            'services.supabase.url' => 'https://supabase.test',
            'services.supabase.key' => 'test-anon-key',
            'services.supabase.service_role_key' => 'test-service-role-key',
        ]);
    }
}
