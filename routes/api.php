<?php

use App\Http\Controllers\Api\V1\AnnouncementController;
use App\Http\Controllers\Api\V1\AssignmentController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\ClassController;
use App\Http\Controllers\Api\V1\DeviceTokenController;
use App\Http\Controllers\Api\V1\GradeController;
use App\Http\Controllers\Api\V1\MaterialController;
use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\QuizController;
use App\Http\Controllers\Api\V1\StudentRegistrationController;
use App\Http\Controllers\Api\V1\SubmissionController;
use App\Http\Controllers\Api\V1\SyncController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->name('api.v1.')->group(function () {
    Route::post('/register', [StudentRegistrationController::class, 'register'])
        ->middleware('throttle:5,1');
    Route::post('/email/verification-notification', [StudentRegistrationController::class, 'resendVerification'])
        ->middleware('throttle:6,1');
    Route::get('/email/verify/{id}/{hash}', [StudentRegistrationController::class, 'verify'])
        ->middleware(['signed', 'throttle:6,1'])
        ->name('email.verify');
    Route::post('/login', [AuthController::class, 'login']);

    // This is the student mobile API. Teacher and admin workflows remain on
    // the existing web application and all data continues to use the same DB.
    Route::middleware(['auth:sanctum', 'active', 'role:student'])->group(function () {
        Route::post('/logout', [AuthController::class, 'logout']);
        Route::get('/me', [AuthController::class, 'me']);

        Route::get('/classes', [ClassController::class, 'index']);
        Route::post('/classes/join', [ClassController::class, 'join']);
        Route::get('/classes/{class}', [ClassController::class, 'show']);

        Route::get('/quizzes', [QuizController::class, 'index']);
        Route::get('/quizzes/{quiz}', [QuizController::class, 'show']);
        Route::get('/quizzes/{quiz}/download', [QuizController::class, 'download']);

        Route::get('/assignments', [AssignmentController::class, 'index']);
        Route::get('/assignments/{assignment}', [AssignmentController::class, 'show']);
        Route::get('/assignments/{assignment}/download', [AssignmentController::class, 'download']);
        Route::get('/assignments/{assignment}/attachment', [AssignmentController::class, 'attachment'])
            ->name('assignments.attachment');

        Route::get('/materials', [MaterialController::class, 'index']);
        Route::get('/materials/{material}', [MaterialController::class, 'show']);
        Route::get('/materials/{material}/download', [MaterialController::class, 'download'])->name('materials.download');
        Route::get('/materials/{material}/file', [MaterialController::class, 'file'])->name('materials.file');

        Route::post('/submissions/quiz', [SubmissionController::class, 'submitQuiz']);
        Route::post('/submissions/assignment', [SubmissionController::class, 'submitAssignment']);

        Route::get('/sync', [SyncController::class, 'index']);
        Route::get('/sync/status', [SyncController::class, 'status']);
        Route::post('/sync', [SyncController::class, 'store']);
        Route::post('/sync/batch', [SyncController::class, 'syncNow']);
        Route::post('/sync/now', [SyncController::class, 'syncNow']);

        Route::get('/grades', [GradeController::class, 'index']);

        Route::get('/announcements', [AnnouncementController::class, 'index']);
        Route::get('/announcements/{announcement}', [AnnouncementController::class, 'show']);
        Route::get('/notifications', [NotificationController::class, 'index']);
        Route::post('/notifications/{notification}/read', [NotificationController::class, 'markAsRead']);
        Route::post('/notifications/read-all', [NotificationController::class, 'markAllAsRead']);
        Route::post('/device-tokens', [DeviceTokenController::class, 'store']);
        Route::delete('/device-tokens', [DeviceTokenController::class, 'destroy']);
    });
});
